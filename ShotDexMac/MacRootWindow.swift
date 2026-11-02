import SwiftUI

/// The Library window (board `Main`, FS-18 01 §1): sidebar 228 with
/// Library, Sources, Collections and Utilities; a toolbar of capsule groups
/// over the content; the grid under it.
struct MacRootWindow: View {
    @Environment(MacDependencies.self) private var dependencies
    @State private var selection: MacSidebarItem? = .allPhotos
    @State private var library: LibraryModel?
    @State private var searchText = ""
    @State private var showsInspector = false
    @State private var showsBackupInspector = true
    /// File › New Backup… asked for the sheet; the Backup screen opens it.
    @State private var opensNewBackup = false
    @State private var serverForm: MacServerFormRequest?
    @State private var smartAlbumForm: MacSmartAlbumFormRequest?
    @State private var smartAlbums: [SmartAlbum] = []
    @State private var viewMode = MacViewMode.grid

    var body: some View {
        NavigationSplitView {
            MacSidebar(selection: $selection, library: library, sources: (try? dependencies.sources.sources()) ?? [],
                       backup: backupBadge, smartAlbums: smartAlbums,
                       newSmartAlbum: { smartAlbumForm = MacSmartAlbumFormRequest() })
                .navigationSplitViewColumnWidth(MacWindowMetrics.sidebarWidth)
        } detail: {
            if selection == .backup {
                MacBackupScreen(showsInspector: $showsBackupInspector, opensNewBackup: $opensNewBackup)
            } else if case .smartAlbum(let id) = selection, let album = smartAlbums.first(where: { $0.id == id }) {
                MacSmartAlbumScreen(album: album, edit: { smartAlbumForm = MacSmartAlbumFormRequest(editing: album) })
            } else {
                libraryDetail
            }
        }
        .tint(MacTheme.accent)
        .task { await start() }
        .onReceive(NotificationCenter.default.publisher(for: .macShowBackup)) { _ in selection = .backup }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            dependencies.onServerCheck.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macAddServer)) { note in
            serverForm = MacServerFormRequest(editing: (note.object as? String).flatMap { try? dependencies.fileServers.fetch(id: $0) })
        }
        .sheet(item: $smartAlbumForm) { request in
            MacSmartAlbumEditorSheet(existing: request.editing) { album in
                smartAlbums = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? []
                selection = .smartAlbum(album.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macNewSmartAlbum)) { _ in smartAlbumForm = MacSmartAlbumFormRequest() }
        .onAppear { smartAlbums = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? [] }
        .sheet(item: $serverForm) { request in
            MacServerFormSheet(editing: request.editing) { _ in
                NotificationCenter.default.post(name: .macServersChanged, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macNewBackup)) { _ in
            selection = .backup
            opensNewBackup = true
        }
    }

    /// Jobs, or a warning when one is stuck on something only the user can
    /// fix (FS-22.06 §5.1).
    private var backupBadge: (jobs: Int, needsAttention: Bool) {
        let coordinator = dependencies.backupCoordinator
        let stuck: Set<BackupJobState.Status> = [.unreachable, .destinationFull, .signInFailed, .noPhotosAccess]
        return (coordinator.jobs.count, coordinator.states.values.contains { stuck.contains($0.status) })
    }

    private var libraryDetail: some View {
            content
                .navigationTitle(selection?.title ?? "ShotDex")
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $searchText, placement: .toolbar,
                            prompt: Text("Canon R6 85mm ISO 3200", comment: "Mac search field placeholder: a sample query"))
                .inspector(isPresented: $showsInspector) {
                    Text("Info", comment: "Mac inspector placeholder")
                        .foregroundStyle(.secondary)
                        .inspectorColumnWidth(MacWindowMetrics.inspectorWidth)
                }
    }

    @ViewBuilder
    private var content: some View {
        if let library, !library.items.isEmpty {
            MacPhotoGrid(items: library.items, photoLibrary: dependencies.photoLibrary, asset: { library.asset(for: $0) },
                         picture: Self.demoPicture)
        } else if dependencies.photoLibrary.authorizationState == .denied {
            ContentUnavailableView(String(localized: "No Access to Photos", comment: "Mac library: Photos access denied"),
                                   systemImage: "photo.on.rectangle",
                                   description: Text("Allow ShotDex in System Settings › Privacy & Security › Photos.",
                                                     comment: "Mac library: how to grant Photos access"))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "54,027 photos · 1,204 videos".
    private var subtitle: String {
        guard let library else { return "" }
        let videos = library.videoCount
        let photos = library.items.count - videos
        var parts = [photos == 1 ? String(localized: "1 photo", comment: "Mac toolbar subtitle")
                                 : String(localized: "\(photos.formatted()) photos", comment: "Mac toolbar subtitle")]
        if videos > 0 {
            parts.append(videos == 1 ? String(localized: "1 video", comment: "Mac toolbar subtitle")
                                     : String(localized: "\(videos.formatted()) videos", comment: "Mac toolbar subtitle"))
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { } label: { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                .disabled(true)
            Button { } label: { Label(String(localized: "Forward", comment: "Mac toolbar"), systemImage: "chevron.right") }
                .disabled(true)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker(selection: $viewMode) {
                Label(String(localized: "Grid", comment: "Mac toolbar view mode"), systemImage: "square.grid.2x2").tag(MacViewMode.grid)
                Label(String(localized: "List", comment: "Mac toolbar view mode"), systemImage: "list.bullet").tag(MacViewMode.list)
            } label: {
                Text("View", comment: "Mac toolbar view mode picker")
            }
            .pickerStyle(.segmented)
            Button { } label: {
                Label(String(localized: "Filter", comment: "Mac toolbar"), systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { } label: { Label(String(localized: "Share", comment: "Mac toolbar"), systemImage: "square.and.arrow.up") }
            Button { showsInspector.toggle() } label: {
                Label(String(localized: "Show Inspector", comment: "Mac toolbar"), systemImage: "sidebar.right")
            }
        }
    }

    private func start() async {
        if library == nil { library = LibraryModel(dependencies: dependencies) }
        #if DEBUG
        if MacDemoLibrary.section == "backup" { selection = .backup }
        if MacDemoLibrary.section == "addServer" { serverForm = MacServerFormRequest() }
        if MacDemoLibrary.section == "newBackup" { selection = .backup; opensNewBackup = true }
        if MacDemoLibrary.section == "smartAlbum" { selection = .smartAlbum("demo-night") }
        if MacDemoLibrary.section == "emptySmartAlbum" { selection = .smartAlbum("demo-empty") }
        if MacDemoLibrary.section == "newSmartAlbum" { smartAlbumForm = MacSmartAlbumFormRequest() }
        if MacDemoLibrary.isOn {
            library?.loadIfNeeded()
            return
        }
        #endif
        if dependencies.photoLibrary.authorizationState == .notDetermined {
            await dependencies.photoLibrary.requestAuthorization()
        }
        // The helper runs the jobs, or the app while it is open (FS-22.06 §2).
        dependencies.backupControl.appStarted()
        // On Server: each time the app comes forward (FS-19.07 §5, §11).
        dependencies.onServerCheck.appBecameActive()
        #if DEBUG
        MacAgentProbe.runIfAsked(dependencies)
        MacSMBProbe.runIfAsked(dependencies) { item in
            smartAlbums = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? []
            selection = item
        }
        #endif
        guard dependencies.photoLibrary.authorizationState.canReadLibrary, let library else { return }
        library.loadIfNeeded()
        library.startIndexing()
    }
}

enum MacViewMode: Hashable { case grid, list }

/// New Smart Album… or editing one.
struct MacSmartAlbumFormRequest: Identifiable {
    let id = UUID()
    var editing: SmartAlbum?
}

/// Add a Server… or Edit Server for one connection.
struct MacServerFormRequest: Identifiable {
    let id = UUID()
    var editing: FileServer?
}

extension MacRootWindow {
    /// The demo library's pictures; nil outside it.
    static var demoPicture: ((String) -> CGImage?)? {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoLibrary.picture(for:) }
        #endif
        return nil
    }
}
