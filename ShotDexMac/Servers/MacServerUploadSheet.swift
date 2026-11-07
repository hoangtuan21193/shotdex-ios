import AppKit
import GRDB
import SwiftUI

/// File › Upload to Server… ⇧⌘U on the selected photos (FS-15.02, Mac).
struct MacUploadRequest: Identifiable, Equatable {
    let id = UUID()
    let photoIds: [String]
}

/// Keeps the Mac awake while files go up, as the iPhone keeps its screen
/// on (FS-15.02b): the system may not idle-sleep mid-batch.
/// Also counts the uploads under way, so Quit can ask first.
/// `@unchecked Sendable`: all state is guarded by `lock`.
final class MacUploadHold: ScreenHolding, @unchecked Sendable {
    private nonisolated let lock = NSLock()
    nonisolated(unsafe) private var activity: NSObjectProtocol?
    /// Uploads holding the Mac awake right now, across windows.
    nonisolated(unsafe) private static var running = 0
    private nonisolated static let countLock = NSLock()

    static var isAnyRunning: Bool { countLock.withLock { running > 0 } }

    /// Never leaves the Mac unable to sleep, however the upload ended.
    deinit { release() }

    func beginHold() {
        lock.withLock {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                             reason: "Uploading photos to a server")
            Self.countLock.withLock { Self.running += 1 }
        }
    }

    func endHold() { release() }

    private nonisolated func release() {
        lock.withLock {
            guard let activity else { return }
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            Self.countLock.withLock { Self.running -= 1 }
        }
    }
}

extension ServerUploadModel {
    /// The upload of `photoIds` with the Mac's stores: originals out of
    /// Photos, one call at a time per connection. Photos the Mac holds only
    /// as files (folders, servers) are not part of an upload yet.
    @MainActor
    static func mac(photoIds: [String], dependencies: MacDependencies) -> ServerUploadModel {
        var listEntries: @Sendable ([String]) async -> [AssetUploadEntry] = { ids in
            await Task.detached(priority: .userInitiated) { PhotoKitOriginalExporter.entries(for: ids) }.value
        }
        var exporter: any AssetFileExporting = PhotoKitOriginalExporter()
        var makeClient: (FileServer, String) -> any RemoteFileClient = RemoteFileClientFactory.make(for:password:)
        #if DEBUG
        if MacDemoLibrary.isOn {
            listEntries = MacDemoUpload.entries(dependencies: dependencies)
            exporter = MacDemoUpload.Exporter()
            makeClient = MacDemoUpload.loopbackOnly
        }
        #endif
        return ServerUploadModel(
            assetIds: photoIds,
            fileServers: dependencies.fileServers,
            uploads: dependencies.serverUploads,
            index: dependencies.serverUploadIndex,
            screenHold: MacUploadHold(),
            listEntries: listEntries,
            makeClient: makeClient,
            connectionLock: dependencies.connectionLock,
            exporter: exporter,
            // The Mac frees space from the On Server place (row 25b), not from here.
            deleteAssets: { _ in }
        )
    }
}

/// The upload sheet (FS-15.02 on the Mac): where the photos go, then their
/// progress, then what happened. One sheet on the Library window — no
/// window of its own (user 2026-11-07).
struct MacServerUploadSheet: View {
    let request: MacUploadRequest
    let close: () -> Void

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openSettings) private var openSettings
    @State private var model: ServerUploadModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().controlSize(.small).frame(width: 520, height: 240)
            }
        }
        .task {
            guard model == nil, !Task.isCancelled else { return }
            let made = ServerUploadModel.mac(photoIds: request.photoIds, dependencies: dependencies)
            model = made
            await made.load()
        }
        // Closed before Upload: nothing started, the browse login and the hold go.
        // After Upload the batch belongs to Activity and keeps going.
        .onDisappear { if model?.stage == .preparing { model?.tearDown() } }
    }

    @ViewBuilder
    private func content(_ model: ServerUploadModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Upload to Server", comment: "Mac upload sheet title").font(.headline)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            prepare(model)
            Divider()
            buttons(model).padding(.horizontal, 20).padding(.vertical, 16)
        }
        .frame(width: 520)
    }

    // MARK: Prepare

    @ViewBuilder
    private func prepare(_ model: ServerUploadModel) -> some View {
        @Bindable var model = model
        if model.servers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No server yet", comment: "Mac upload: no connection is set up").font(.body.weight(.semibold))
                Text("Add a connection to a NAS or a computer in Settings › Servers, then upload again.",
                     comment: "Mac upload: how to add the first connection")
                    .foregroundStyle(.secondary)
                Button(String(localized: "Open Servers Settings…", comment: "Mac upload: go add a connection")) {
                    close()
                    openSettings()
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        } else {
            Form {
                Picker(String(localized: "Connection", comment: "Mac upload: which server"),
                       selection: Binding(get: { model.selectedServerId }, set: { model.select($0) })) {
                    ForEach(model.servers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { server in
                        Text(server.name).tag(Optional(server.id))
                    }
                }
                TextField(String(localized: "Folder", comment: "Mac upload: the folder on the server"), text: $model.folder,
                          prompt: Text("Top of the share", comment: "Mac upload: empty folder = the share's top"))
                Toggle(String(localized: "Date Folders", comment: "Mac upload: year and day folders"), isOn: $model.usesDateFolders)
                Text(model.usesDateFolders
                     ? String(localized: "Photos go into year and day folders inside this folder, by the day they were taken.",
                              comment: "Mac upload: Date Folders on")
                     : String(localized: "Photos go straight into this folder.", comment: "Mac upload: Date Folders off"))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(String(localized: "Files", comment: "Mac upload: which files of each photo"), selection: $model.fileKind) {
                    ForEach(ServerUploadFileKind.allCases) { Text($0.title).tag($0) }
                }
                summaryLine(model)
            }
            .formStyle(.grouped)
            // A sheet does not inherit the window's tint: the switch amber, never system blue (MAC_STYLE).
            .tint(MacTheme.accent)
            // Room for every row and the summary; the notes under it scroll when there are several.
            .frame(height: 284)
        }
    }

    @ViewBuilder
    private func summaryLine(_ model: ServerUploadModel) -> some View {
        if let summary = model.planSummary {
            let bytes = ByteCountFormatter.string(fromByteCount: summary.estimatedBytes, countStyle: .file)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(summary.photoCount) photos · \(summary.fileCount) files · ~\(bytes)", comment: "Mac upload: what goes up")
                    .monospacedDigit()
                let notInPhotos = model.assetIds.count - (model.entries?.count ?? 0)
                if summary.skippedPhotoCount > 0 {
                    Text("\(summary.skippedPhotoCount) have no RAW and will be skipped.", comment: "Mac upload: Only RAW leaves some out")
                        .foregroundStyle(.secondary)
                }
                if notInPhotos > 0 {
                    Text("\(notInPhotos) aren't in Photos and aren't uploaded from here yet.",
                         comment: "Mac upload: folder or server photos are left out")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading the photos…", comment: "Mac upload: listing each photo's files").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private func buttons(_ model: ServerUploadModel) -> some View {
        HStack {
            Spacer()
            Button(String(localized: "Cancel", comment: "Mac upload: close without uploading"), action: close)
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .keyboardShortcut(.cancelAction)
            if !model.servers.isEmpty {
                Button(String(localized: "Upload", comment: "Mac upload: start")) { upload(model) }
                    .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
        }
    }

    /// Upload: the batch goes to Activity, which opens on it — the window
    /// stays usable while the files go up (MAC_STYLE: long work never in a sheet).
    private func upload(_ model: ServerUploadModel) {
        guard dependencies.uploads.start(model) else { NSSound.beep(); return }
        close()
        MacWindowRequest.showsActivity = true
        NotificationCenter.default.post(name: .macShowActivity, object: nil)
    }
}

#if DEBUG
/// The demo library's photos are rows, not Photos assets: each uploads as
/// one JPEG drawn from its demo picture, so the flow runs against the local
/// test SMB server and never touches a real library.
enum MacDemoUpload {
    @MainActor
    static func entries(dependencies: MacDependencies) -> @Sendable ([String]) async -> [AssetUploadEntry] {
        let database = dependencies.database
        return { ids in
            // The demo database's rows, not the window's grid, which may be filtered to another place.
            let rows = (try? await database.reader.read { db in
                try Dictionary(Row.fetchAll(db, sql: "SELECT assetId, originalFilename, creationDate FROM photo_metadata")
                    .map { ($0["assetId"] as String, (name: $0["originalFilename"] as String?, date: $0["creationDate"] as Int?)) },
                    uniquingKeysWith: { first, _ in first })
            }) ?? [:]
            return ids.compactMap { id -> AssetUploadEntry? in
                guard let row = rows[id] else { return nil }
                let name = ((row.name ?? "\(id).JPG") as NSString).deletingPathExtension + ".JPG"
                let date = row.date.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                let file = AssetUploadFile(key: "demo:\(name)", filename: name, isRAW: false, role: .original, estimatedBytes: 400_000)
                return AssetUploadEntry(assetId: id, captureDate: date, files: [file], takenAt: date)
            }
        }
    }

    /// The demo's own connection rows name LAN hosts (`nas.local`): a demo
    /// upload may only ever reach the local test server. Any other host is
    /// pointed at a closed port on this Mac, so it fails as unreachable.
    static func loopbackOnly(_ server: FileServer, password: String) -> any RemoteFileClient {
        var safe = server
        if !["127.0.0.1", "localhost", "::1"].contains(server.host) {
            safe.host = "127.0.0.1"
            safe.port = 9
        }
        return RemoteFileClientFactory.make(for: safe, password: password)
    }

    struct Exporter: AssetFileExporting {
        func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
            let image = await MainActor.run { MacDemoLibrary.picture(for: assetId) }
            guard let image else { throw CocoaError(.fileNoSuchFile) }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.filename)
            try data?.write(to: url)
            return url
        }
    }
}
#endif
