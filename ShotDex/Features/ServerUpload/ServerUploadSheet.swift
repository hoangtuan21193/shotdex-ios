import ImageIO
import SwiftUI

/// Selection ⋯ → Upload to Server (FS-15.02). One sheet, four states:
/// prepare, uploading, a conflict inside uploading, and the result with the
/// offer to delete. Tier A — it is a form and a report, not a canvas.
struct ServerUploadSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ServerUploadModel
    @State private var isAddingServer = false
    @State private var isConfirmingCancel = false
    @State private var isConfirmingDelete = false

    init(model: ServerUploadModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.stage == .uploading)
        .task {
            await model.load()
            if model.servers.isEmpty { isAddingServer = true }
        }
        .sheet(isPresented: $isAddingServer) {
            FileServerFormScreen(draft: FileServerDraft()) { saved in
                model.reloadServers(select: saved.id)
            }
        }
        // Leaving the app stops the batch the way Cancel does: iOS gives a
        // background app seconds, and a half-sent RAW is worth nothing.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.stage == .uploading { model.cancel() }
        }
        .onDisappear { model.tearDown() }
        .alert("Stop Uploading?", isPresented: $isConfirmingCancel) {
            Button("Stop", role: .destructive) { model.cancel() }
            Button("Keep Uploading", role: .cancel) {}
        } message: {
            Text("Files already uploaded stay on the server.")
        }
        .alert(
            deleteTitle,
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteUploaded() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They move to Recently Deleted and free up space after 30 days, or when you empty it in Photos. If iCloud Photos is on, they are also deleted from iCloud and your other devices.")
        }
        .alert(
            "Couldn't Delete Photos",
            isPresented: Binding(get: { model.deleteError != nil }, set: { if !$0 { model.deleteError = nil } }),
            presenting: model.deleteError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var title: String {
        switch model.stage {
        case .preparing: String(localized: "Upload to Server")
        case .uploading: model.pendingConflict == nil ? String(localized: "Uploading") : String(localized: "File Already Exists")
        case .finished: String(localized: "Upload Finished")
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete \(model.summary.deletableAssetIds.count) Photos from This Device?", comment: "Upload to Server: confirm deleting the uploaded photos")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.stage {
        case .preparing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Upload") { model.start() }
                    .disabled(!model.canStart)
            }
        case .uploading:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isConfirmingCancel = true }
            }
        case .finished:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .preparing: prepareForm
        case .uploading:
            if let conflict = model.pendingConflict {
                ServerUploadConflictView(conflict: conflict, model: model)
            } else {
                progressView
            }
        case .finished: resultForm
        }
    }

    // MARK: Prepare

    private var prepareForm: some View {
        Form {
            Section("Server") {
                if model.servers.isEmpty {
                    Button("Add Server…") { isAddingServer = true }
                } else {
                    Picker("Server", selection: $model.selectedServerId) {
                        ForEach(model.servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                    if let server = model.selectedServer {
                        LabeledContent("Folder", value: "\(server.transferProtocol.title) · \(server.locationDescription)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Add Server…") { isAddingServer = true }
                }
            }
            Section {
                Picker("Files", selection: $model.fileKind) {
                    ForEach(ServerUploadFileKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Files")
            } footer: {
                summaryFooter
            }
            Section {
                Label("Keep ShotDex open until the upload finishes. The screen stays on.", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var summaryFooter: some View {
        if let summary = model.planSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summary.photoCount) photos · \(summary.fileCount) files · ~\(ByteCountFormatter.string(fromByteCount: summary.estimatedBytes, countStyle: .file))",
                     comment: "Upload to Server prepare summary: photos, files and estimated size")
                if summary.skippedPhotoCount > 0 {
                    Text("\(summary.skippedPhotoCount) have no RAW and will be skipped.",
                         comment: "Upload to Server, Only RAW: photos without a RAW file")
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading files…")
            }
        }
    }

    // MARK: Progress

    private var progressView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Uploading \(model.progress.fileIndex + 1) of \(model.progress.fileCount)",
                         comment: "Upload to Server progress headline")
                        .font(.headline)
                    ProgressView(value: model.progress.fraction)
                        .accessibilityLabel("Upload progress")
                        .accessibilityValue(Text(model.progress.fraction, format: .percent.precision(.fractionLength(0))))
                    Text(byteLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                LabeledContent(model.progress.filename, value: phaseTitle(model.progress.phase))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } footer: {
                Text("Keep ShotDex open until the upload finishes. The screen stays on.")
            }
        }
    }

    private var byteLine: String {
        let done = ByteCountFormatter.string(fromByteCount: model.progress.bytesDone / 2, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: model.progress.bytesTotal / 2, countStyle: .file)
        guard let seconds = model.progress.secondsLeft else {
            return String(localized: "\(done) of \(total)", comment: "Upload to Server: bytes sent of total")
        }
        let left = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return String(localized: "\(done) of \(total) · about \(left) left", comment: "Upload to Server: bytes sent of total, and time left")
    }

    private func phaseTitle(_ phase: ServerUploadPhase) -> String {
        switch phase {
        case .preparing: String(localized: "Preparing", comment: "Upload to Server: reading the original out of Photos / iCloud")
        case .uploading: String(localized: "Uploading", comment: "Upload to Server: sending the file")
        case .verifying: String(localized: "Verifying", comment: "Upload to Server: reading the file back to check its checksum")
        }
    }

    // MARK: Result

    private var resultForm: some View {
        let summary = model.summary
        return Form {
            Section {
                if summary.uploadedPhotoCount > 0 {
                    Text("Uploaded \(summary.uploadedPhotoCount) photos (\(ByteCountFormatter.string(fromByteCount: summary.uploadedBytes, countStyle: .file))) to \(model.selectedServer?.name ?? "")",
                         comment: "Upload to Server result headline")
                        .font(.headline)
                } else {
                    Text("Nothing was uploaded.")
                        .font(.headline)
                }
                if let stop = summary.stopMessage {
                    Text(stop).foregroundStyle(.secondary)
                }
                if summary.skippedFileCount > 0 {
                    Text("\(summary.skippedFileCount) files skipped because they were already on the server.",
                         comment: "Upload to Server result: files the user chose to skip")
                        .foregroundStyle(.secondary)
                }
            }
            if !summary.deletableAssetIds.isEmpty {
                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        HStack {
                            Label("Delete \(summary.deletableAssetIds.count) from This Device", systemImage: "trash")
                                // The glyph otherwise keeps the list's blue
                                // beside the red text.
                                .foregroundStyle(.red)
                            if model.isDeleting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isDeleting)
                } footer: {
                    Text("Only photos whose every original file is verified on a server are included.")
                }
            }
            if !summary.partiallyUploaded.isEmpty {
                Section {
                    ForEach(summary.partiallyUploaded.sorted(by: { $0.key < $1.key }), id: \.key) { _, missing in
                        Text("Kept on this device — \(missing.joined(separator: ", ")) not on a server",
                             comment: "Upload to Server result: a photo that cannot be deleted yet, and which of its files are missing")
                            .font(.footnote)
                    }
                } header: {
                    Text("Not Offered for Deletion")
                }
            }
            if !summary.failures.isEmpty || summary.notAttemptedCount > 0 {
                Section {
                    ForEach(summary.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.filename)
                            Text(failure.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if summary.notAttemptedCount > 0 {
                        Text("\(summary.notAttemptedCount) files not uploaded yet.", comment: "Upload to Server result: files the stopped batch never reached")
                            .foregroundStyle(.secondary)
                    }
                    if model.hasRemaining {
                        Button(summary.uploadedPhotoCount == 0 ? "Try Again" : "Upload Remaining") {
                            model.uploadRemaining()
                        }
                    }
                } header: {
                    Text("Not Uploaded")
                }
            }
        }
    }
}

/// Same name on the server (FS-15.02 §5): the two files side by side, and
/// the three answers.
private struct ServerUploadConflictView: View {
    let conflict: ServerUploadConflict
    let model: ServerUploadModel
    @State private var appliesToRemaining = false
    @State private var localImage: CGImage?
    @State private var remoteImage: CGImage?
    @State private var isLoadingRemote = true

    var body: some View {
        Form {
            Section {
                Text("\(conflict.item.file.filename) is already in this folder on the server, with different contents.",
                     comment: "Upload to Server conflict explanation")
                HStack(alignment: .top, spacing: 12) {
                    side(title: String(localized: "On This Device"), image: localImage, isLoading: false, bytes: conflict.localBytes)
                    side(title: String(localized: "On Server"), image: remoteImage, isLoading: isLoadingRemote, bytes: conflict.remoteBytes)
                }
                .padding(.vertical, 4)
            }
            Section {
                // Red: it overwrites the file already on the server.
                Button("Replace", role: .destructive) { answer(.replace) }
                Button("Keep Both") { answer(.keepBoth) }
                Button("Skip") { answer(.skip) }
                Toggle("Apply to Remaining Conflicts", isOn: $appliesToRemaining)
            } footer: {
                Text("Keep Both saves the new file under the next free name, such as \(ServerUploadPath.nextFreeName(for: conflict.item.file.filename, existing: [conflict.item.file.filename])).",
                     comment: "Upload to Server conflict: how Keep Both names the new file")
            }
        }
        .task(id: conflict.id) {
            localImage = Self.thumbnail(of: conflict.localURL)
            isLoadingRemote = true
            if let url = await model.downloadConflictPreview(conflict) {
                remoteImage = Self.thumbnail(of: url)
                try? FileManager.default.removeItem(at: url)
            }
            isLoadingRemote = false
        }
    }

    private func answer(_ choice: ServerUploadConflictDecision.Choice) {
        model.answerConflict(.init(choice: choice, appliesToRemaining: appliesToRemaining))
    }

    private func side(title: String, image: CGImage?, isLoading: Bool, bytes: Int64) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(Color(.secondarySystemBackground))
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(title).font(.subheadline.weight(.semibold))
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// A 400px thumbnail straight from the file — ImageIO reads RAW, HEIC and
    /// JPEG alike, and never decodes the full frame.
    private static func thumbnail(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension EnvironmentValues {
    /// Selection ⋯ → Upload to Server. Set by each window's root, which owns
    /// the sheet: the ids travel up to the window they were picked in, never
    /// to a shared coordinator another window could also be presenting from.
    /// Nil outside a root (previews), and the menu row is then left out.
    @Entry var presentServerUpload: PresentServerUploadAction? = nil
}

/// The value behind `presentServerUpload`: call it with the picked ids.
///
/// A struct rather than a bare closure so SwiftUI can compare it. A root
/// hands in a fresh closure on every body pass, and a closure never compares
/// equal, so every screen reading the key re-rendered whenever the root did.
/// Each of those closures only sets that root's own `@State`, so any two do
/// the same thing — equal by definition.
struct PresentServerUploadAction: Equatable {
    let handler: ([String]) -> Void

    func callAsFunction(_ assetIds: [String]) { handler(assetIds) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// The picked ids, frozen at the tap.
struct ServerUploadRequest: Identifiable {
    let id = UUID()
    let assetIds: [String]
}

/// Builds the model from the environment the sheet is presented in.
struct ServerUploadHost: View {
    @Environment(AppDependencies.self) private var dependencies
    let request: ServerUploadRequest

    var body: some View {
        ServerUploadSheet(model: ServerUploadModel(assetIds: request.assetIds, dependencies: dependencies))
    }
}
