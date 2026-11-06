import AppKit
import SwiftUI

/// Settings › Sources › Photo Sources (board `MAC_SettingsSources`, AC-72):
/// every source with what it holds and how it is, and what can be done to
/// it — Manage Access for Photos, Re-index and Remove… for the rest, Grant
/// Access… when a folder can no longer be opened.
struct MacPhotoSourcesSection: View {
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @State private var removing: SourcesModel.Row?
    @State private var isDropTargeted = false

    private var model: SourcesModel { dependencies.sourcesModel }

    var body: some View {
        Section {
            ForEach(model.rows) { row in
                MacSourceRow(row: row, isReading: model.readingSourceId == row.id, isAnyReading: model.readingSourceId != nil,
                             reindex: { reindex(row) }, grantAccess: { grantAccess(row) }, remove: { removing = row })
            }
            HStack(spacing: 8) {
                Text(isDropTargeted ? String(localized: "Release to add", comment: "Mac Settings › Sources: a folder is over the drop row")
                                    : String(localized: "Drop a folder here", comment: "Mac Settings › Sources: the row that takes a dropped folder"))
                    .foregroundStyle(isDropTargeted ? MacTheme.accent : .secondary)
                Spacer()
                Button(String(localized: "Add Folder…", comment: "Mac Settings › Sources: add a folder source"), action: addFolder)
                    .disabled(model.readingSourceId != nil)
                Button(String(localized: "Connect to Server…", comment: "Mac Settings › Sources: add a server connection")) {
                    // The form is a sheet on the Library window: bring it forward first.
                    MacMainWindow.bringForward(openWindow)
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        NotificationCenter.default.post(name: .macAddServer, object: nil)
                    }
                }
                .help(String(localized: "Opens in the Library window", comment: "Mac Settings › Sources: where Connect to Server opens"))
            }
            .padding(.vertical, 4)
            .listRowBackground(isDropTargeted ? MacTheme.accentSoft : nil)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Photo Sources", comment: "Mac Settings › Sources group")
                Spacer()
                if let aside { Text(aside).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
        } footer: {
            Text("Folders, drives and servers are indexed in place. ShotDex never changes your files.",
                 comment: "Mac Settings › Sources footer")
                .foregroundStyle(.secondary)
        }
        // A folder dropped anywhere on the group is added (AC-73); files and
        // anything but one folder are not taken.
        .dropDestination(for: URL.self) { urls, _ in
            if let refusal = SourcesModel.dropRefusal(urls, isReading: model.readingSourceId != nil) {
                model.failure = SourcesModel.Failure(title: String(localized: "Can’t Add This", comment: "Mac Settings › Sources: a drop was refused"),
                                                     message: refusal)
                return false
            }
            add(urls[0])
            return true
        } isTargeted: { isDropTargeted = $0 }
        .task {
            #if DEBUG
            await MacDemoSources.seedIfAsked(dependencies)
            #endif
            model.load()
        }
        .confirmationDialog(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { row in
            Button(String(localized: "Remove", comment: "Mac Settings › Sources: confirm Remove Source"), role: .destructive) {
                Task {
                    await model.remove(sourceId: row.id)
                    dependencies.folderRoots.forget(row.id)
                }
            }
            Button(String(localized: "Cancel", comment: "Mac Settings › Sources: keep the source"), role: .cancel) {}
        } message: { row in
            Text(row.text.removeMessage)
        }
        .alert(model.failure?.title ?? "",
               isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Settings › Sources: dismiss an error")) {}
        } message: {
            Text(model.failure?.message ?? "")
        }
    }

    /// `Indexing 22%` while a run goes, so it shows without scrolling to
    /// Index. No total of the rows: a photo two sources hold would count twice.
    private var aside: String? {
        guard let library = dependencies.library, library.isIndexing,
              let fraction = IndexStatusLine.fraction(.indexing(processed: library.indexProgress?.processed ?? 0,
                                                                total: library.indexProgress?.total ?? 0)) else { return nil }
        return String(localized: "Indexing \(Int((fraction * 100).rounded(.down)))%",
                      comment: "Mac Settings › Sources header: index progress, e.g. Indexing 22%")
    }

    private var removeTitle: String {
        guard let removing else { return "" }
        return String(localized: "Remove “\(removing.name)”?", comment: "Mac Settings › Sources: Remove Source dialog title")
    }

    private func addFolder() {
        Self.chooseFolder { add($0) }
    }

    /// Add Folder's open panel, here and on the sidebar's + (board `Main`).
    static func chooseFolder(_ picked: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add Folder", comment: "Mac Sources: the open panel's button")
        panel.message = String(localized: "Choose a folder or drive of photos. ShotDex reads it in place and never changes its files.",
                               comment: "Mac Sources: Add Folder panel message")
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let folder = panel.url else { return }
            picked(folder)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    /// Subfolders in, RAW + JPEG as pairs: the defaults Add Source uses on iOS.
    private func add(_ folder: URL) {
        Task { await model.addFolder(folder, includesSubfolders: true, pairsRawAndJpeg: true) }
    }

    private func reindex(_ row: SourcesModel.Row) {
        Task {
            if case .server = row.text.kind {
                await model.rescanServer(sourceId: row.id)
            } else {
                await model.read(sourceId: row.id)
            }
        }
    }

    private func grantAccess(_ row: SourcesModel.Row) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Grant Access", comment: "Mac Sources: the open panel's button")
        panel.message = String(localized: "Choose “\(row.name)” so ShotDex can read it again.",
                               comment: "Mac Sources: open panel message for Grant Access")
        // Where it was, when the bookmark still says.
        if let path = model.lastKnownPath(sourceId: row.id) { panel.directoryURL = path.deletingLastPathComponent() }
        let picked: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let folder = panel.url else { return }
            dependencies.folderRoots.forget(row.id)
            Task { await model.grantAccess(sourceId: row.id, folder: folder) }
        }
        // A sheet on Settings, not a window of its own; never a modal that blocks the app.
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: picked) } else { panel.begin(completionHandler: picked) }
    }
}

/// One source: an icon tile, the name with its kind, the detail line with a
/// status dot, and its buttons.
private struct MacSourceRow: View {
    let row: SourcesModel.Row
    let isReading: Bool
    /// Any source reading: one read at a time, so the others wait too.
    let isAnyReading: Bool
    let reindex: () -> Void
    let grantAccess: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tile, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(1)
                    Text(row.text.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 4))
                }
                HStack(spacing: 5) {
                    Circle().fill(dotColor).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(row.text.detail())
                        .foregroundStyle(row.text.needsAttention ? Color.red : .secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            buttons
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            switch row.text.kind {
            case .photos:
                Button(String(localized: "Manage Access…", comment: "Mac Settings › Sources: open Photos privacy settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .accessibilityLabel(String(localized: "Manage Photos access", comment: "Mac Settings › Sources: VoiceOver"))
            default:
                if row.text.status == .needsAccess {
                    Button(String(localized: "Grant Access…", comment: "Mac Settings › Sources: pick a folder again"), action: grantAccess)
                        .disabled(isAnyReading)
                        .buttonStyle(.borderedProminent)
                        .tint(MacTheme.accent)
                        .accessibilityLabel(String(localized: "Grant Access to \(row.name)", comment: "Mac Settings › Sources: VoiceOver"))
                } else {
                    Button(String(localized: "Re-index", comment: "Mac Settings › Sources: read a source again"), action: reindex)
                        .disabled(isAnyReading || row.text.status == .offline)
                        .help(isAnyReading ? String(localized: "Already reading", comment: "Mac Settings › Sources: why Re-index is off")
                              : row.text.status == .offline ? String(localized: "Not connected", comment: "Mac Settings › Sources: why Re-index is off")
                              : String(localized: "Read this source again", comment: "Mac Settings › Sources: Re-index help"))
                        .accessibilityLabel(String(localized: "Re-index \(row.name)", comment: "Mac Settings › Sources: VoiceOver"))
                }
                Button(String(localized: "Remove…", comment: "Mac Settings › Sources: remove a source"), action: remove)
                    .disabled(isReading)
                    .accessibilityLabel(String(localized: "Remove \(row.name)", comment: "Mac Settings › Sources: VoiceOver"))
            }
        }
    }

    private var symbol: String {
        switch row.text.kind {
        case .photos: "photo.on.rectangle"
        case .drive: "externaldrive"
        case .server: "server.rack"
        case .onDevice, .iCloudDrive: "folder"
        }
    }

    /// The board's tile colours: Photos pink, folders blue, drives grey, servers indigo.
    private var tile: Color {
        switch row.text.kind {
        case .photos: .pink
        case .drive: .gray
        case .server: .indigo
        case .onDevice, .iCloudDrive: .blue
        }
    }

    private var dotColor: Color {
        switch row.text.dot {
        case .ok: .green
        case .away: .gray
        case .attention: .red
        }
    }
}
