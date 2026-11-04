import SwiftUI

/// The Library window (board `Main`, FS-18 01 §1): sidebar 228 with
/// Library, Sources, Collections and Utilities; a toolbar of capsule groups
/// over the content; the grid under it.
struct MacRootWindow: View {
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
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
    /// The sidebar's sources, read when they change — not on every body.
    @State private var sources: [SourceStore.Source] = []

    var body: some View {
        NavigationSplitView {
            MacSidebar(selection: $selection, library: library, sources: sources,
                       backup: backupBadge, smartAlbums: smartAlbums,
                       newSmartAlbum: { smartAlbumForm = MacSmartAlbumFormRequest() },
                       busyFooter: dependencies.commonPhotos.footRunId.map { AnyView(MacCommonPhotosFoot(runId: $0)) })
                .navigationSplitViewColumnWidth(MacWindowMetrics.sidebarWidth)
        } detail: {
            if selection == .backup {
                MacBackupScreen(showsInspector: $showsBackupInspector, opensNewBackup: $opensNewBackup)
            } else if let source = serverSource {
                MacServerBrowserScreen(source: source)
            } else if case .smartAlbum(let id) = selection, let album = smartAlbums.first(where: { $0.id == id }) {
                MacSmartAlbumScreen(album: album, edit: { smartAlbumForm = MacSmartAlbumFormRequest(editing: album) })
            } else {
                libraryDetail
            }
        }
        .tint(MacTheme.accent)
        .onAppear { reloadSources() }
        .onChange(of: dependencies.sourcesModel.rows) { reloadSources() }
        .onChange(of: selection) { reloadSources() }
        // Show CSV in Browser (FS-19.08 §7): the run's source opens; its
        // browser goes to the destination.
        .onChange(of: dependencies.commonPhotos.browserRequest?.path) {
            guard let request = dependencies.commonPhotos.browserRequest else { return }
            // One source per connection; sorted, so two would pick the same one every time.
            guard let sourceId = ((try? dependencies.sources.serverConnections()) ?? [:])
                .filter({ $0.value == request.connectionId }).keys.sorted().first
            else {
                dependencies.commonPhotos.browserRequest = nil
                return
            }
            selection = .source(sourceId)
        }
        // Keep gathering's notice clicked (FS-19.08 §6c): the run's window.
        .onChange(of: dependencies.commonPhotos.logRequest?.runId, initial: true) {
            guard let request = dependencies.commonPhotos.logRequest else { return }
            dependencies.commonPhotos.logRequest = nil
            guard Date().timeIntervalSince(request.at) < 60 else { return }
            openWindow(id: MacCommonPhotosRunWindow.id, value: request.runId)
        }
        // Run Again (FS-19.08 §6c): the run's source opens; its browser
        // opens the sheet on the run's set.
        .onChange(of: dependencies.commonPhotos.runAgainRequest?.id, initial: true) {
            guard let run = dependencies.commonPhotos.runAgainRequest else { return }
            guard let sourceId = ((try? dependencies.sources.serverConnections()) ?? [:])
                .filter({ $0.value == run.connectionId }).keys.sorted().first
            else {
                dependencies.commonPhotos.runAgainRequest = nil
                return
            }
            selection = .source(sourceId)
        }
        .background(MacMainWindowMarker())
        .onReceive(NotificationCenter.default.publisher(for: .macServersChanged)) { _ in reloadSources() }
        .task { await start() }
        .onReceive(NotificationCenter.default.publisher(for: .macShowBackup)) { _ in selection = .backup }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            dependencies.backupControl.appBecameActive()
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
        // Settings › General › Indexing: "Index Now" reads what originals-only
        // skipped, with iCloud allowed; a changed switch starts a fresh run.
        .onReceive(NotificationCenter.default.publisher(for: .macIndexMissingNow)) { _ in
            library?.reindexIncompleteAssets(manual: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macIndexSettingsChanged)) { _ in
            library?.startIndexing()
        }
    }

    /// The server source picked in the sidebar: its browser fills the
    /// content (board `MAC_ServerBrowser`, FS-19.03 §4).
    private var serverSource: SourceStore.Source? {
        guard case .source(let id) = selection else { return nil }
        return sources.first { $0.id == id && $0.kind == "server" }
    }

    private func reloadSources() {
        sources = (try? dependencies.sources.sources()) ?? []
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
        // One model for every Library window, so a window reopened during a
        // run shows that run and Settings reads the same progress.
        if library == nil { library = dependencies.library ?? LibraryModel(dependencies: dependencies) }
        dependencies.library = library
        #if DEBUG
        if MacDemoLibrary.section == "backup" { selection = .backup }
        if MacDemoLibrary.section == "addServer" { serverForm = MacServerFormRequest() }
        if MacDemoLibrary.section == "newBackup" { selection = .backup; opensNewBackup = true }
        if MacDemoLibrary.section == "smartAlbum" { selection = .smartAlbum("demo-night") }
        if MacDemoLibrary.section == "onNAS" { selection = .smartAlbum(OnServerMismatchDemo.albumId) }
        if MacDemoLibrary.section == "emptySmartAlbum" { selection = .smartAlbum("demo-empty") }
        if MacDemoLibrary.section == "newSmartAlbum" { smartAlbumForm = MacSmartAlbumFormRequest() }
        if MacDemoLibrary.section == "settings" { openSettings() }
        // With `-ShotDexOriginalCheck`: the album on the Original rule, or its editor.
        if MacDemoLibrary.section == "originalAlbum" { selection = .smartAlbum(MacDemoLibrary.originalAlbumId) }
        if MacDemoLibrary.section == "editOriginalAlbum" {
            selection = .smartAlbum(MacDemoLibrary.originalAlbumId)
            smartAlbumForm = MacSmartAlbumFormRequest(editing: (try? dependencies.smartAlbums.fetchAllOrdered())?
                .first { $0.id == MacDemoLibrary.originalAlbumId })
        }
        if ProcessInfo.processInfo.arguments.contains("-ShotDexOpenActivity") { openWindow(id: MacActivityWindow.id) }
        // `-ShotDexLogMenus`: what the Window menu holds, with its keys, to the log.
        if ProcessInfo.processInfo.arguments.contains("-ShotDexLogMenus") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                for item in NSApp.mainMenu?.items ?? [] where item.title == "Window" {
                    for entry in item.submenu?.items ?? [] where !entry.isSeparatorItem {
                        let mods = entry.keyEquivalentModifierMask
                        let keys = (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "")
                            + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + entry.keyEquivalent
                        MacAgentProbe.log.notice("window menu: \(entry.title, privacy: .public) \(entry.keyEquivalent.isEmpty ? "" : keys, privacy: .public)")
                    }
                }
            }
        }
        if MacDemoLibrary.section == "serverBrowser", let item = await MacDemoLibrary.seedServerSource(dependencies) {
            reloadSources()
            selection = item
        }
        if MacDemoLibrary.isOn {
            library?.readsGridFromIndex = true
            library?.loadIfNeeded()
            return
        }
        #endif
        if dependencies.photoLibrary.authorizationState == .notDetermined {
            await dependencies.photoLibrary.requestAuthorization()
        }
        // The helper runs the jobs and the On Server check, or the app while
        // it is open (FS-22.06 §2, FS-19.07 §11); appStarted starts this
        // side's pass when the app is the runner.
        dependencies.backupControl.appStarted()
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
