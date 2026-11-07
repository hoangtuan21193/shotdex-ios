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
    /// The search suggestions' vocabulary and how the parser reads the field.
    @State private var searchReading: [String] = []
    /// The scope bar's choice; the library holds its condition, rebuilt when
    /// the sources change.
    @State private var searchScope = MacSearchScope.all
    @State private var searchCameras: [String] = []
    @State private var searchLenses: [String] = []
    @FocusState private var isSearchFocused: Bool
    /// The grid's rules came from the search field (they share the slot
    /// with Advanced Filter): emptying the field takes them away again.
    @State private var searchOwnsQuery = false
    /// ⌘F asked for the field while the grid (and so the field) was not on
    /// screen: the grid takes it when it appears.
    @State private var wantsSearchFocus = false
    /// The `emptyLibrary` demo's stand-in for the Photos permission.
    @State private var demoPhotosAdded = false
    /// Add Photos Library… is waiting on macOS's prompt: a second click waits too.
    @State private var isAddingPhotos = false
    /// Add a Source (board `MAC_AddSource`) and what it asked for, run once
    /// it has closed — the open panel and the server form are window sheets.
    @State private var showsAddSource = false
    @State private var addSourceRequest: MacAddSourceRequest?
    /// Add Photos Library… came back without access.
    @State private var showsPhotosDenied = false
    @State private var showsInspector = false
    /// On This Day's day (FS-06.07 §4): only its month and day are matched.
    @State private var onThisDayDate = MacOnThisDayDatePicker.day(of: Date())
    @State private var showsDatePicker = false
    /// "Hanoi, Vietnam" per year for On This Day's headers.
    @State private var onThisDayPlaces: [Int: String] = [:]
    /// How many years the day's photos span, counted off the main actor.
    @State private var onThisDayYears = 0
    @State private var showsBackupInspector = true
    /// File › New Backup… asked for the sheet; the Backup screen opens it.
    @State private var opensNewBackup = false
    @State private var serverForm: MacServerFormRequest?
    @State private var smartAlbumForm: MacSmartAlbumFormRequest?
    @State private var smartAlbums: [SmartAlbum] = []
    /// Why the sidebar's Add Folder… could not add (Settings shows its own).
    @State private var addFolderFailure: SourcesModel.Failure?
    /// Grid or list (FS-18.02 §3), kept between launches.
    @AppStorage("mac.library.viewMode") private var viewMode = MacViewMode.grid
    /// The list view's extra columns, by asset id.
    @State private var tableDetails: [String: LibraryTableQueries.Details] = [:]
    /// Bumped on each read of `tableDetails`, so the table sees a new read
    /// even when it holds as many photos as the last one.
    @State private var tableDetailsGeneration = 0
    /// The sidebar's sources, read when they change — not on every body.
    @State private var sources: [SourceStore.Source] = []
    /// Filter and Sort (FS-18.02 §5): the popover, its Advanced Filter…
    /// sheet, and the bar of chips under the toolbar.
    @State private var showsFilterPopover = false
    @State private var showsAdvancedFilter = false
    @AppStorage(MacFilterBar.visibilityKey) private var showsFilterBar = true
    /// The whole library, the M of "N of M photos": the grid's count when
    /// nothing narrows it.
    @State private var libraryTotal: Int?
    /// The unfiltered library holds a video: the filtered line says items.
    @State private var libraryHasVideos = false
    /// The filtered grid's last settled count, shown while a reload runs —
    /// so the line and the empty state do not flicker on each one.
    @State private var settledMatchCount: Int?
    /// The sidebar's counts (FS-18.01 §2), read off the main actor.
    @State private var placeCounts: [MacSidebarItem: Int] = [:]
    /// When the index last finished, for the sidebar foot; read off the main actor.
    @State private var lastIndexedAt: Date?
    @State private var indexRunsEnded = 0
    /// The source whose read banner the user closed: the foot keeps the line.
    @State private var hiddenReadBannerId: String?
    /// Remove Source… asked on an offline banner, waiting for its confirmation.
    @State private var removingSource: SourcesModel.Row?
    /// Locate… picked a folder that holds few of the source's files: asked first.
    @State private var unlikelyLocate: MacUnlikelyLocate?
    /// Photos only on offline sources: their tiles carry the offline glyph.
    @State private var offlinePhotoIds: Set<String> = []
    /// The right-click menu on photos (board `MAC_ContextMenu`), grid and list.
    @State private var photoMenu: MacPhotoMenu?
    /// The photos selected in the grid or list, and their summary (inspector).
    @State private var photoSelection: MacSelectionModel?

    var body: some View {
        root.focusedSceneValue(\.macGo, MacGoTarget(go: { selection = $0 },
                                                      chooseDate: selection == .onThisDay ? { showsDatePicker = true } : nil))
    }

    private var root: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if selection == .backup {
                MacBackupScreen(showsInspector: $showsBackupInspector, opensNewBackup: $opensNewBackup)
            } else if let source = serverSource {
                MacServerBrowserScreen(source: source)
            } else if case .smartAlbum(let id) = selection, let album = smartAlbums.first(where: { $0.id == id }) {
                MacSmartAlbumScreen(album: album, edit: { smartAlbumForm = MacSmartAlbumFormRequest(editing: album) })
            } else if let selection, selection.isPendingScreen {
                MacPendingPlace(item: selection)
            } else {
                libraryDetail
            }
        }
        .tint(MacTheme.accent)
        .onAppear { reloadSources() }
        .onChange(of: dependencies.sourcesModel.rows) { reloadSources() }
        .onChange(of: selection) {
            // Only a row that shows the grid moves it: Backup or Statistics
            // must not reload 55k rows nobody sees.
            if let selection, isGridPlace(selection) {
                libraryTotal = nil
                libraryHasVideos = false
                // Words typed but never searched do not follow to the next place.
                if !searchOwnsQuery { searchText = "" }
                // A scope is part of a search: it does not follow to the next place on its own.
                if !searchOwnsQuery { library?.sourceScope = nil }
                // On This Day has no filter (board): a Library filter must not narrow it unseen.
                // It opens on today; a day picked last visit is not kept.
                if selection == .onThisDay {
                    if !searchOwnsQuery {
                        library?.criteria = .empty
                        library?.advancedQuery = nil
                    }
                    onThisDayDate = MacOnThisDayDatePicker.day(of: Date())
                }
                library?.place = place(for: selection)
            }
        }
        // One LibraryModel serves every Library window: the key window's
        // place is the one it shows.
        .background(MacKeyWindowObserver { if let selection, isGridPlace(selection) { library?.place = place(for: selection) } })
        // Another day picked: the grid follows (only its month and day count).
        .onChange(of: onThisDayDate) {
            guard selection == .onThisDay else { return }
            onThisDayPlaces = [:]
            library?.place = place(for: selection)
        }
        // Each year's place for the headers, read on GRDB's pool.
        .task(id: selection == .onThisDay ? "\(onThisDayDate)-\(library?.rowsGeneration ?? 0)-\(library?.items.count ?? 0)" : "") {
            guard selection == .onThisDay, let ids = library?.items.map(\.assetId), !ids.isEmpty else {
                if !onThisDayPlaces.isEmpty { onThisDayPlaces = [:] }
                onThisDayYears = 0
                return
            }
            let items = library?.items ?? []
            let years = await Task.detached(priority: .userInitiated) {
                let calendar = Calendar.current
                return Set(items.compactMap { $0.creationDateValue.map { calendar.component(.year, from: $0) } }).count
            }.value
            let places = (try? await dependencies.libraryQueries.placesByYear(ids: ids)) ?? [:]
            guard !Task.isCancelled else { return }
            if years != onThisDayYears { onThisDayYears = years }
            if places != onThisDayPlaces { onThisDayPlaces = places }
        }
        .task(id: countsKey) { await reloadPlaceCounts() }
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
        .modifier(MacRootRequests(root: self))
    }

    /// The menu commands' and the app's requests to this window — split from
    /// `body` so the type checker can take it.
    fileprivate func requests(_ content: some View) -> some View {
        alerts(content)
            .modifier(MacPhotoMenuHostIfReady(menu: photoMenu, library: library, selection: photoSelection))
            .background(MacMainWindowMarker())
            .onReceive(NotificationCenter.default.publisher(for: .macServersChanged)) { _ in reloadSources() }
            .task { await start() }
            .onReceive(NotificationCenter.default.publisher(for: .macShowBackup)) { _ in selection = .backup }
            // Edit › Search ⌘F: search is the grid's, so from Backup or a server
            // All Photos opens first and its field takes the focus once it exists.
            .onReceive(NotificationCenter.default.publisher(for: .macFocusSearchRequest)) { _ in
                guard selection.map(isGridPlace) != true else {
                    NotificationCenter.default.post(name: .macFocusSearch, object: nil)
                    return
                }
                wantsSearchFocus = true
                selection = .allPhotos
            }
            // ⇧⌘O and ⌘K wait while Add a Source is open: one sheet at a time.
            .onReceive(NotificationCenter.default.publisher(for: .macAddFolder)) { _ in
                if !showsAddSource { addFolderFromSidebar() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .macViewMode)) { note in
                if let mode = (note.object as? String).flatMap(MacViewMode.init(rawValue:)) { viewMode = mode }
            }
            .onReceive(NotificationCenter.default.publisher(for: .macShowAddSource)) { _ in
                addSourceRequest = nil
                showsAddSource = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .macAddPhotosLibrary)) { _ in addPhotosLibrary() }
            .onReceive(NotificationCenter.default.publisher(for: .macGoTo)) { note in
                if let item = note.object as? MacSidebarItem { selection = item }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                dependencies.backupControl.appBecameActive()
                // Back from System Settings › Photos with access allowed.
                if dependencies.photoLibrary.refreshAuthorization(), dependencies.photoLibrary.authorizationState.canReadLibrary {
                    photosBecameReadable()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .macAddServer)) { note in
                guard !showsAddSource else { return }
                serverForm = MacServerFormRequest(editing: (note.object as? String).flatMap { try? dependencies.fileServers.fetch(id: $0) })
            }
            .sheet(item: $smartAlbumForm) { request in
                MacSmartAlbumEditorSheet(existing: request.editing, initialQuery: request.query, onSaved: { album in
                    smartAlbums = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? []
                    selection = .smartAlbum(album.id)
                })
            }
            .onReceive(NotificationCenter.default.publisher(for: .macNewSmartAlbum)) { _ in smartAlbumForm = MacSmartAlbumFormRequest() }
            .onAppear { smartAlbums = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? [] }
            .sheet(isPresented: $showsAddSource, onDismiss: runAddSourceRequest) {
                MacAddSourceSheet(photosAdded: photosAdded,
                                  addPhotosLibrary: { addSourceRequest = .photos },
                                  addFolder: { addSourceRequest = .folder($0, includesSubfolders: $1, pairsRawAndJpeg: $2) },
                                  connectToServer: { addSourceRequest = .server })
            }
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

    /// Why an add did not happen, at the window's root: the sidebar may be hidden.
    private func alerts(_ content: some View) -> some View {
        content
            .alert(addFolderFailure?.title ?? "",
                   isPresented: Binding(get: { addFolderFailure != nil }, set: { if !$0 { addFolderFailure = nil } })) {
                Button(String(localized: "OK", comment: "Mac alert: dismiss")) {}
            } message: {
                Text(addFolderFailure?.message ?? "")
            }
            .alert(String(localized: "ShotDex Can’t Read Your Photos Library", comment: "Mac alert: Photos access refused"),
                   isPresented: $showsPhotosDenied) {
                Button(String(localized: "Open System Settings", comment: "Mac alert: go to Privacy › Photos")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                }
                Button(String(localized: "Not Now", comment: "Mac alert: dismiss"), role: .cancel) {}
            } message: {
                Text("Allow ShotDex in System Settings › Privacy & Security › Photos. Folders, drives and servers work without it.",
                     comment: "Mac alert: how to grant Photos access")
            }
    }

    /// The server source picked in the sidebar: its browser fills the
    /// content (board `MAC_ServerBrowser`, FS-19.03 §4).
    /// The sidebar, with what its + › Add Folder… could not add.
    private var sidebar: some View {
        // The first run counts nothing (board `MAC_EmptyLibrary`): no row of zeros.
        MacSidebar(selection: $selection, library: library, counts: isLibraryEmpty ? [:] : placeCounts,
                   sources: photosAdded ? sources : sources.filter { $0.kind != "photos" },
                   backup: backupBadge, smartAlbums: smartAlbums,
                   newSmartAlbum: { smartAlbumForm = MacSmartAlbumFormRequest() },
                   addSource: {
                       // A request left by a close that never reached onDismiss is not run later.
                       addSourceRequest = nil
                       showsAddSource = true
                   },
                   addFolders: { addFolders($0) },
                   lastIndexedAt: lastIndexedAt,
                   sourcesModel: dependencies.sourcesModel,
                   showReadBanner: { hiddenReadBannerId = nil },
                   busyFooter: dependencies.commonPhotos.footRunId.map { AnyView(MacCommonPhotosFoot(runId: $0)) })
            // Read at open, at a run's start and end — `.indexRunEnded` also
            // covers the runs that found nothing to do and never flip isIndexing.
            .task(id: "\(library?.isIndexing == true)-\(indexRunsEnded)") {
                let store = dependencies.metadataStore
                let read = await Task.detached(priority: .utility) {
                    (try? store.indexState())?.lastIndexedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                }.value
                guard !Task.isCancelled else { return }
                lastIndexedAt = read
            }
            .onReceive(NotificationCenter.default.publisher(for: .indexRunEnded)) { _ in indexRunsEnded &+= 1 }
            // A new read shows its banner again, whatever was closed before.
            .onChange(of: dependencies.sourcesModel.readingSourceId) { _, reading in
                if reading != nil { hiddenReadBannerId = nil }
            }
            .navigationSplitViewColumnWidth(MacWindowMetrics.sidebarWidth)
    }

    private var serverSource: SourceStore.Source? {
        guard case .source(let id) = selection else { return nil }
        return sources.first { $0.id == id && $0.kind == "server" }
    }

    /// Photos was added as a source: its permission was asked (FS-18.01 §7
    /// asks only on Add Photos Library…, never at launch). Read straight from
    /// the observable permission, so the first frame is already right.
    private var photosAdded: Bool {
        #if DEBUG
        if MacDemoLibrary.section == "emptyLibrary" { return demoPhotosAdded }
        if MacDemoLibrary.isOn { return true }
        #endif
        // Refused counts as not added: the welcome screen stays, and its
        // Add Photos Library… says where to allow it.
        return dependencies.photoLibrary.authorizationState.canReadLibrary
    }

    /// No source yet (board `MAC_EmptyLibrary`): Photos not added and no
    /// folder, drive or server.
    private var isLibraryEmpty: Bool {
        !photosAdded && !sources.contains { $0.kind != "photos" }
    }

    /// Add Photos Library…: macOS asks now, not at launch. Access granted, the
    /// grid loads and the index starts; refused, the alert says where to fix it.
    private func addPhotosLibrary() {
        #if DEBUG
        if MacDemoLibrary.section == "emptyLibrary" {
            // The demo's Photos is its seeded rows; the real permission is not asked.
            Task {
                await MacDemoLibrary.seedRows(dependencies)
                demoPhotosAdded = true
                library?.reload()
            }
            return
        }
        #endif
        guard !isAddingPhotos else { return }
        isAddingPhotos = true
        Task {
            defer { isAddingPhotos = false }
            // Allowed in System Settings since the last look: no prompt, no alert.
            dependencies.photoLibrary.refreshAuthorization()
            if dependencies.photoLibrary.authorizationState == .notDetermined {
                await dependencies.photoLibrary.requestAuthorization()
            }
            guard dependencies.photoLibrary.authorizationState.canReadLibrary else {
                showsPhotosDenied = true
                return
            }
            photosBecameReadable()
        }
    }

    /// Photos is readable now: the grid loads and the index starts.
    private func photosBecameReadable() {
        library?.loadIfNeeded()
        library?.reload()
        library?.startIndexing()
    }

    /// Folders, drives or cards — dropped on the window or the sidebar, or
    /// picked with Add Folder or Drive…. Every one is tried; what could not
    /// be added is said once, after.
    private func addFolders(_ urls: [URL], includesSubfolders: Bool = true, pairsRawAndJpeg: Bool = true) {
        let folders = urls.filter(MacEmptyLibrary.isFolder)
        if folders.isEmpty {
            addFolderFailure = SourcesModel.Failure(
                title: String(localized: "Drop a Folder", comment: "Mac alert: something other than a folder was dropped"),
                message: String(localized: "ShotDex adds folders, drives and memory cards. To read your Photos library, use Add Photos Library….",
                                comment: "Mac alert: a file or a Photos library package was dropped"))
            return
        }
        let model = dependencies.sourcesModel
        Task {
            var failures: [SourcesModel.Failure] = []
            for folder in folders {
                await model.addFolder(folder, includesSubfolders: includesSubfolders, pairsRawAndJpeg: pairsRawAndJpeg)
                if let failure = model.failure {
                    model.failure = nil
                    failures.append(failure)
                }
            }
            reloadSources()
            library?.loadIfNeeded()
            library?.reload()
            if let first = failures.first {
                addFolderFailure = failures.count == 1 ? first : SourcesModel.Failure(
                    title: first.title,
                    message: failures.map(\.message).joined(separator: "\n\n"))
            }
        }
    }

    /// The row shows the library grid (and so its search field).
    private func isGridPlace(_ item: MacSidebarItem) -> Bool {
        switch item {
        case .allPhotos, .favorites, .videos, .raw, .recentlyAdded, .onThisDay: true
        case .source: serverSource == nil
        default: false
        }
    }

    /// What the grid shows for a sidebar row; nil is the whole library.
    private func place(for item: MacSidebarItem?) -> LibraryPlace? {
        switch item {
        case .favorites: .favorites
        case .videos: .videos
        case .raw: .raw
        case .recentlyAdded: .recentlyAdded
        case .onThisDay:
            .onThisDay(month: Calendar.current.component(.month, from: onThisDayDate),
                       day: Calendar.current.component(.day, from: onThisDayDate))
        case .source(let id): .source(id)
        default: nil
        }
    }

    /// Recounted when the library, the index or the sources change — not on
    /// every body. The grid's own count stands in for "a file was indexed".
    private var countsKey: String {
        "\(dependencies.photoLibrary.assetChangeToken)-\(library?.isIndexing == true)-\(sources.map(\.id))"
    }

    /// What an empty place says (FS-18.01 §2).
    private var emptyPlaceTitle: String {
        switch selection {
        case .favorites: String(localized: "No Favorites", comment: "Mac library: Favorites is empty")
        case .videos: String(localized: "No Videos", comment: "Mac library: Videos is empty")
        case .raw: String(localized: "No RAW Photos", comment: "Mac library: RAW is empty")
        case .recentlyAdded: String(localized: "Nothing Added Recently", comment: "Mac library: Recently Added is empty")
        case .onThisDay: String(localized: "Nothing from \(onThisDayDate.formatted(.dateTime.month(.wide).day()))",
                                comment: "Mac On This Day: no photo on this day in earlier years")
        default: String(localized: "No Photos", comment: "Mac library: a source with no photos")
        }
    }

    /// The window title: the row's name — a source's own name, not "Source".
    private var placeTitle: String {
        if case .source(let id) = selection, let source = sources.first(where: { $0.id == id }) { return source.name }
        return selection?.title ?? "ShotDex"
    }

    /// All Photos, Favorites, Videos, RAW and each source, counted on GRDB's
    /// pool so a click never waits on them. Waits a beat first: an index run
    /// changes the key often, and only the last change needs counting.
    private func reloadPlaceCounts() async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let queries = dependencies.libraryQueries
        var counts: [MacSidebarItem: Int] = [:]
        if let all = await library?.wholeLibraryCount() { counts[.allPhotos] = all }
        var places: [(MacSidebarItem, LibraryPlace)] = [(.favorites, .favorites), (.videos, .videos), (.raw, .raw)]
        places += sources.filter { $0.kind != "server" }.map { (.source($0.id), .source($0.id)) }
        for (item, place) in places {
            guard !Task.isCancelled else { return }
            if let filters = try? await place.filters(), let count = try? await queries.count(matchingAll: filters) {
                counts[item] = count
            }
        }
        guard !Task.isCancelled else { return }
        placeCounts = counts
    }

    private func reloadSources() {
        sources = (try? dependencies.sources.sources()) ?? []
    }

    /// The first run's Add Folder or Drive… and File › Add Folder…: what
    /// Settings › Sources adds, with its defaults; the failure said here rather
    /// than in a Settings window that may be shut.
    private func addFolderFromSidebar() {
        MacPhotoSourcesSection.chooseFolder { addFolders([$0]) }
    }

    private func runAddSourceRequest() {
        guard let request = addSourceRequest else { return }
        addSourceRequest = nil
        switch request {
        case .photos: addPhotosLibrary()
        case .folder(let folder, let subfolders, let pairs):
            addFolders([folder], includesSubfolders: subfolders, pairsRawAndJpeg: pairs)
        case .server: serverForm = MacServerFormRequest()
        }
    }

    /// Jobs, or a warning when one is stuck on something only the user can
    /// fix (FS-22.06 §5.1).
    private var backupBadge: (jobs: Int, needsAttention: Bool) {
        let coordinator = dependencies.backupCoordinator
        let stuck: Set<BackupJobState.Status> = [.unreachable, .destinationFull, .signInFailed, .noPhotosAccess]
        return (coordinator.jobs.count, coordinator.states.values.contains { stuck.contains($0.status) })
    }

    /// Drives and servers not connected (FS-19.01b §2), each with its banner.
    private var offlineSources: [SourcesModel.Row] {
        dependencies.sourcesModel.rows.filter { $0.text.status == .offline }
    }

    @ViewBuilder
    private var sourceBanners: some View {
        MacSourceReadBannerHost(model: dependencies.sourcesModel, hiddenSourceId: $hiddenReadBannerId)
        // One offline source, or the one picked in the sidebar: its banner.
        // Several elsewhere: one line, so shelved drives don't eat the grid.
        let shown = offlineSources.count == 1 ? offlineSources : offlineSources.filter { selection == .source($0.id) }
        ForEach(shown) { row in
            let isServer = if case .server = row.text.kind { true } else { false }
            MacSourceOfflineBanner(name: row.name, photoCount: row.text.count, isServer: isServer,
                                   locate: { locate(row) }, remove: { removingSource = row })
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        if offlineSources.count > 1, shown.isEmpty {
            MacOfflineSummary(names: offlineSources.map(\.name)) { name in
                if let row = offlineSources.first(where: { $0.name == name }) { selection = .source(row.id) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    /// Remove Source…'s message: what leaves, what stays, by drive or server.
    private var removeSourceMessage: String {
        guard let row = removingSource else { return "" }
        let isServer = if case .server = row.text.kind { true } else { false }
        return isServer
            ? String(localized: "Its \(row.text.count) photos leave ShotDex unless another source has a copy. Ratings and edits are kept for 30 days in case you add it back. Nothing on the server is deleted.",
                     comment: "Mac: Remove Source confirmation, a server (plural)")
            : String(localized: "Its \(row.text.count) photos leave ShotDex unless another source has a copy. Ratings and edits are kept for 30 days in case you add it back. Nothing on the drive is deleted.",
                     comment: "Mac: Remove Source confirmation, a drive or folder (plural)")
    }

    /// Locate…: the folder's new place; read back to the same photos (FS-19.01b §2).
    /// Not while another read runs, and a folder holding almost none of the
    /// source's files is asked about first — read against the wrong folder,
    /// every photo would be marked missing.
    private func locate(_ row: SourcesModel.Row) {
        let model = dependencies.sourcesModel
        guard model.readingSourceId == nil else {
            addFolderFailure = SourcesModel.Failure(
                title: String(localized: "Can’t Locate Now", comment: "Mac: Locate while a source is read"),
                message: String(localized: "Wait for the current read to finish, then locate “\(row.name)” again.",
                                comment: "Mac: Locate while a source is read"))
            return
        }
        MacPhotoSourcesSection.chooseFolder(startingAt: model.lastKnownPath(sourceId: row.id)?.deletingLastPathComponent()) { folder in
            let queries = CopyReachabilityQueries(database: dependencies.database)
            Task {
                let paths = (try? await queries.knownPaths(sourceId: row.id)) ?? []
                let found = await Task.detached(priority: .userInitiated) {
                    let scoped = folder.startAccessingSecurityScopedResource()
                    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                    return paths.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }.count
                }.value
                if paths.isEmpty || found * 5 >= paths.count {
                    await model.grantAccess(sourceId: row.id, folder: folder)
                } else {
                    unlikelyLocate = MacUnlikelyLocate(row: row, folder: folder, found: found, checked: paths.count)
                }
            }
        }
    }

    private var libraryDetail: some View {
            VStack(spacing: 0) {
                sourceBanners
                // Once a search is run, or a scope set — not while words are only typed.
                if let library, searchOwnsQuery || library.sourceScope != nil {
                    MacSearchScopeBar(scope: Binding(get: { searchScope }, set: { setScope($0) }), count: subtitle,
                                      canSave: canSaveSearch,
                                      saveAsSmartAlbum: { smartAlbumForm = MacSmartAlbumFormRequest(query: savedSearchQuery) })
                }
                if let library, showsFilterBar, !library.criteria.isEmpty || library.advancedQuery?.isEmpty == false {
                    MacFilterBar(library: library)
                }
                content
            }
                // Which photos are offline, read again when a source comes or goes.
                .task(id: "\(offlineSources.map(\.id))-\(dependencies.sourcesModel.readCount)") {
                    guard !offlineSources.isEmpty else { offlinePhotoIds = []; return }
                    let queries = CopyReachabilityQueries(database: dependencies.database)
                    let ids = (try? await queries.offlinePhotoIds()) ?? []
                    guard !Task.isCancelled, ids != offlinePhotoIds else { return }
                    offlinePhotoIds = ids
                }
                .onChange(of: library.map { "\($0.items.count)-\($0.isLoading)-\($0.hasActiveQuery)" }, initial: true) {
                    guard let library, !library.isLoading else { return }
                    if library.hasActiveQuery {
                        settledMatchCount = library.items.count
                    } else {
                        settledMatchCount = nil
                        libraryTotal = library.items.count
                        libraryHasVideos = library.videoCount > 0
                    }
                }
                // While filtered, M follows the library: a change in Photos,
                // an index run ending — read from the unfiltered grid's source.
                .task(id: "\(selection?.id ?? "")-\(library?.hasActiveQuery == true)-\(dependencies.photoLibrary.assetChangeToken)-\(library?.isIndexing == true)") {
                    guard let library, library.hasActiveQuery else { return }
                    if let total = await library.unfilteredCount(), !Task.isCancelled { libraryTotal = total }
                }
                .macWatchesOriginalOnDevice(library?.criteria.originalOnDeviceOnly == true) { library?.reload() }
                .onReceive(NotificationCenter.default.publisher(for: .macShowFilterPopover)) { _ in
                    // On This Day has no filter (board `MAC_OnThisDay`): say so, not nothing.
                    if selection == .onThisDay { NSSound.beep() } else { showsFilterPopover = true }
                }
                .sheet(isPresented: $showsAdvancedFilter) {
                    MacSmartAlbumEditorSheet(initialQuery: libraryQuery,
                                             applyFilter: {
                                                 searchOwnsQuery = false
                                                 library?.advancedQuery = $0.isEmpty ? nil : $0
                                             })
                }
                .alert(removingSource.map { String(localized: "Remove “\($0.name)”?", comment: "Mac: Remove Source confirmation title") } ?? "",
                       isPresented: Binding(get: { removingSource != nil }, set: { if !$0 { removingSource = nil } })) {
                    Button(String(localized: "Remove", comment: "Mac: confirm Remove Source"), role: .destructive) {
                        guard let row = removingSource else { return }
                        Task { await dependencies.sourcesModel.remove(sourceId: row.id) }
                    }
                    Button(String(localized: "Cancel", comment: "Mac: keep the source"), role: .cancel) {}
                } message: {
                    Text(removeSourceMessage)
                }
                .alert(String(localized: "This Folder Doesn’t Look Like “\(unlikelyLocate?.row.name ?? "")”", comment: "Mac: Locate picked another folder"),
                       isPresented: Binding(get: { unlikelyLocate != nil }, set: { if !$0 { unlikelyLocate = nil } })) {
                    Button(String(localized: "Use This Folder", comment: "Mac: Locate anyway"), role: .destructive) {
                        guard let pick = unlikelyLocate else { return }
                        Task { await dependencies.sourcesModel.grantAccess(sourceId: pick.row.id, folder: pick.folder) }
                    }
                    Button(String(localized: "Cancel", comment: "Mac: keep the source where it was"), role: .cancel) {}
                } message: {
                    Text("Only \(unlikelyLocate?.found ?? 0) of \(unlikelyLocate?.checked ?? 0) files checked are in “\(unlikelyLocate?.folder.lastPathComponent ?? "")”. Using it marks the photos it lacks as missing.",
                         comment: "Mac: Locate picked a folder with few of the source's files")
                }                .navigationTitle(placeTitle)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $searchText, placement: .toolbar,
                            prompt: isLibraryEmpty ? Text("Search", comment: "Mac search field placeholder before any photo")
                                                   : Text("Canon R6 85mm ISO 3200", comment: "Mac search field placeholder: a sample query"))
                .searchFocused($isSearchFocused)
                .searchSuggestions { searchSuggestions }
                // The suggestions, a beat after typing stops: the parser's
                // reading, and the cameras and lenses matching the word being
                // typed (matched off the main actor; the vocabulary is cached).
                .task(id: searchText) {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let text = searchText
                    let reading = await dependencies.search.preview(text)
                    let catalog = await dependencies.filterSuggestions.load()
                    let tails = MacSearchSuggestions.tail(text.trimmingCharacters(in: .newlines))
                    let (cameras, lenses) = await Task.detached(priority: .userInitiated) {
                        (MacSearchSuggestions.matches(tails, in: catalog.bodies), MacSearchSuggestions.matches(tails, in: catalog.lenses))
                    }.value
                    guard !Task.isCancelled, text == searchText else { return }
                    (searchReading, searchCameras, searchLenses) = (reading, cameras, lenses)
                }
                .onReceive(NotificationCenter.default.publisher(for: .macFocusSearch)) { _ in isSearchFocused = true }
                .onAppear {
                    guard wantsSearchFocus else { return }
                    wantsSearchFocus = false
                    isSearchFocused = true
                }
                // Return searches (FS-18.02 §4); an emptied field shows the
                // grid again at once. Parsing runs off the main actor.
                .onSubmit(of: .search) {
                    searchOwnsQuery = true
                    library?.applySearch(searchText, using: dependencies.search)
                }
                // A Reset (filter bar, popover, empty state) that empties the
                // grid's query takes the search words with it.
                .onChange(of: library?.hasActiveQuery == true) {
                    if library?.hasActiveQuery == false, searchOwnsQuery {
                        searchOwnsQuery = false
                        searchText = ""
                    }
                }
                .onChange(of: searchText) {
                    guard searchText.trimmingCharacters(in: .whitespaces).isEmpty, let library else { return }
                    library.applySearch("", using: dependencies.search)
                    // Clearing a search clears its scope too: back to the whole grid.
                    if searchOwnsQuery {
                        library.advancedQuery = nil
                        setScope(.all)
                    }
                    searchOwnsQuery = false
                }
                // A source added or gone: the scope's condition names the sources anew.
                .onChange(of: sources) { if searchScope != .all { library?.sourceScope = searchScope.query(sources: sources) } }
                // Every Reset that drops the condition drops the choice with it.
                .onChange(of: library?.sourceScope == nil) { _, isNil in if isNil { searchScope = .all } }
                .inspector(isPresented: $showsInspector) {
                    Group {
                        if let photoSelection, let photoMenu {
                            MacSelectionInspector(selection: photoSelection, menu: photoMenu, picture: Self.demoPicture)
                        }
                    }
                    .inspectorColumnWidth(MacWindowMetrics.inspectorWidth)
                }
                .focusedSceneValue(\.macLibrary, libraryTarget)
    }

    /// The menu bar's way into this window's library (FS-18.01b §2).
    private var libraryTarget: MacLibraryTarget? {
        guard let library, let photoMenu else { return nil }
        // Read when the command runs: a key right after a click acts on the new selection.
        let selection = photoSelection
        var ids: [String] { selection?.ids ?? [] }
        return MacLibraryTarget(
            hasSelection: !(selection?.ids.isEmpty ?? true),
            showsInspector: showsInspector,
            sort: library.sort,
            quickLook: { photoMenu.quickLook(ids) },
            showInFinder: { photoMenu.showInFinder(ids) },
            toggleFavorite: { photoMenu.toggleFavorite(ids) },
            rate: { photoMenu.apply(.rate($0), to: ids) },
            flag: { photoMenu.apply(.flag($0), to: ids) },
            moveToTrash: { photoMenu.moveToTrash(ids) },
            advancedSearch: { showsAdvancedFilter = true },
            toggleInspector: { showsInspector.toggle() },
            setSort: { library.sort = $0 })
    }

    private func patchDetails() async {
        guard let ids = photoMenu?.changedIds, !ids.isEmpty else { return }
        let queries = LibraryTableQueries(database: dependencies.database)
        guard let changed = try? await queries.details(ids: ids), !Task.isCancelled else { return }
        let old = tableDetails
        let patched = await Task.detached(priority: .userInitiated) {
            var details = old
            for id in ids { details[id] = changed[id] }
            return details
        }.value
        guard !Task.isCancelled else { return }
        tableDetails = patched
        tableDetailsGeneration += 1
        Task.detached(priority: .utility) { _ = old }
    }

    /// The photo menu, told which photos are offline as it opens.
    /// Image's single keys while the grid or list has the keyboard; the
    /// selection is read when the key comes, not when the view was built.
    private var markKey: ((NSEvent) -> Bool)? {
        guard let photoMenu else { return nil }
        let selection = photoSelection
        return { photoMenu.markKey($0, ids: selection?.ids ?? []) }
    }

    private var photoMenuBuilder: (([String]) -> NSMenu?)? {
        guard let photoMenu else { return nil }
        let offline = offlinePhotoIds
        return { ids in
            photoMenu.offline = offline
            return photoMenu.menu(for: ids)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLibraryEmpty {
            MacEmptyLibrary(addPhotosLibrary: addPhotosLibrary, addFolder: { addFolderFromSidebar() },
                            connectToServer: { serverForm = MacServerFormRequest() }, addFolders: { addFolders($0) })
        } else if let library, !library.items.isEmpty {
            Group {
                if viewMode == .list, selection != .onThisDay {
                    MacPhotoTable(items: library.items, generation: library.rowsGeneration, details: tableDetails,
                                  detailsGeneration: tableDetailsGeneration, photoLibrary: dependencies.photoLibrary,
                                  assetAt: { library.asset(atFlatIndex: library.items.count - 1 - $0) },
                                  assetGeneration: library.contentRefreshGeneration, picture: Self.demoPicture,
                                  sort: library.sort, setSort: { library.sort = $0 },
                                  onSelection: { photoSelection?.set($0) }, contextMenu: photoMenuBuilder,
                                  markKey: markKey,
                                  initialSelection: photoSelection?.idSet ?? [])
                } else {
                    // Newest-first position i is the model's (bottom-anchored) count − 1 − i.
                    MacPhotoGrid(items: library.items, photoLibrary: dependencies.photoLibrary, asset: { library.asset(for: $0) },
                                 picture: Self.demoPicture,
                                 yearHeaders: selection == .onThisDay ? MacYearHeaders(currentYear: Calendar.current.component(.year, from: Date()), showsAge: isOnThisDayToday, places: onThisDayPlaces) : nil,
                                 endKey: selection == .onThisDay ? "\(onThisDayDate)" : nil,
                                 offline: offlinePhotoIds, onSelection: { photoSelection?.set($0) },
                                 initialSelection: photoSelection?.idSet ?? [],
                                 contextMenu: photoMenuBuilder, markKey: markKey, marks: tableDetails, marksGeneration: tableDetailsGeneration,
                                 generation: library.rowsGeneration,
                                 assetAt: { library.asset(atFlatIndex: library.items.count - 1 - $0) },
                                 assetGeneration: library.contentRefreshGeneration)
                }
            }
            // Camera, lens, marks, source (list columns and tile marks): one
            // read of the index, off the main actor — again when the set of
            // photos or a mark changes, not on a sort. An index run changes
            // the count often: the read waits for a pause, and a read like
            // the last one is not handed over.
            .task(id: "\(library.items.count)-\(library.place.map { "\($0)" } ?? "")-\(dependencies.photoLibrary.assetChangeToken)") {
                if !tableDetails.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
                let marksAtStart = photoMenu?.marksGeneration
                let queries = LibraryTableQueries(database: dependencies.database)
                let old = tableDetails
                guard let details = try? await queries.details(), !Task.isCancelled else { return }
                let isSame = await Task.detached(priority: .userInitiated) { details == old }.value
                guard !isSame, !Task.isCancelled else { return }
                tableDetails = details
                tableDetailsGeneration += 1
                // The old 55k entries are let go off the main actor.
                Task.detached(priority: .utility) { _ = old }
                // A mark changed while the library was read: the read may
                // predate it, so those photos are read again.
                if photoMenu?.marksGeneration != marksAtStart { await patchDetails() }
            }
            // A star, flag or favorite: only those photos are read again
            // and patched in, off the main actor.
            .task(id: photoMenu?.marksGeneration ?? 0) { await patchDetails() }
        } else if let library, let error = library.loadError {
            ContentUnavailableView {
                Label(error, systemImage: "exclamationmark.triangle")
            } actions: {
                Button(String(localized: "Try Again", comment: "Mac library: load the grid again")) { library.reload() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let library, library.criteria.originalOnDeviceOnly,
                  let line = dependencies.originalPresenceCheck.partialLine {
            // Unchecked photos match neither way (FS-06.10 §3): the grid is
            // filling, not empty.
            ContentUnavailableView {
                Label(String(localized: "Checking Originals", comment: "Mac library: Original on This Mac, check still running"),
                      systemImage: "desktopcomputer")
            } description: {
                Text(line).monospacedDigit()
            } actions: {
                Button(MacFilterCopy.resetFilters) {
                    library.criteria = .empty
                    library.advancedQuery = nil
                    library.sourceScope = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let library, library.hasActiveQuery, !library.isLoading || settledMatchCount == 0 {
            ContentUnavailableView {
                Label(String(localized: "No Photos Match", comment: "Mac library: the filter leaves nothing"),
                      systemImage: "line.3.horizontal.decrease")
            } description: {
                if library.sourceScope != nil {
                    Text(MacInfoScopeText.empty(searchScope, sources: sources))
                } else {
                    Text("No photo matches the current filters.", comment: "Mac library: empty filtered grid")
                }
            } actions: {
                if library.sourceScope != nil {
                    Button(String(localized: "Search All Sources", comment: "Mac library: drop only the source scope")) { setScope(.all) }
                }
                Button(MacFilterCopy.resetFilters) {
                    library.criteria = .empty
                    library.advancedQuery = nil
                    library.sourceScope = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let library, !library.isLoading, library.items.isEmpty, !library.hasActiveQuery, library.place != nil {
            // A place with nothing in it says so; the spinner is only for loading.
            if selection == .onThisDay {
                ContentUnavailableView {
                    Label(emptyPlaceTitle, systemImage: selection?.systemImage ?? "photo")
                } description: {
                    Text("No photo was taken on this day in an earlier year.", comment: "Mac On This Day: empty, why")
                } actions: {
                    Button(String(localized: "Choose Date…", comment: "Mac On This Day: pick another day")) { showsDatePicker = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(emptyPlaceTitle, systemImage: selection?.systemImage ?? "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if dependencies.photoLibrary.authorizationState == .denied {
            ContentUnavailableView(String(localized: "No Access to Photos", comment: "Mac library: Photos access denied"),
                                   systemImage: "photo.on.rectangle",
                                   description: Text("Allow ShotDex in System Settings › Privacy & Security › Photos.",
                                                     comment: "Mac library: how to grant Photos access"))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "54,027 photos · 1,204 videos", or "212 of 55,231 photos" while a
    /// filter is on (FS-18.02 §5).
    private var subtitle: String {
        if isLibraryEmpty { return String(localized: "No photos yet", comment: "Mac toolbar subtitle: no source added yet") }
        guard let library else { return "" }
        // "6 selected · 214.8 MB" (board `MAC_LibrarySelected`); the size
        // follows once the selection's summary is read.
        if let photoSelection, !photoSelection.ids.isEmpty {
            let count = String(localized: "\(photoSelection.ids.count) selected", comment: "Mac toolbar subtitle: photos selected (plural)")
            guard let summary = photoSelection.summary else { return count }
            return count + " · " + ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file)
        }
        if selection == .onThisDay { return onThisDayLine(library) }
        let shown = library.hasActiveQuery && library.isLoading ? settledMatchCount ?? library.items.count : library.items.count
        let line = LibraryCountLine.text(shown: shown, videos: library.videoCount, total: libraryTotal,
                                         isFiltered: library.hasActiveQuery, libraryHasVideos: libraryHasVideos)
        // "55,267 photos · 1,204 videos · 26,107 offline" (FS-19.01b §2), in the whole library.
        // Photos with no copy that opens now — not every photo a drive holds.
        let offline = offlinePhotoIds.count
        guard offline > 0, library.place == nil, !library.hasActiveQuery else { return line }
        return line + " · " + String(localized: "\(offline) offline", comment: "Mac toolbar subtitle: photos on sources not connected")
    }

    /// The day picked is today's month and day.
    private var isOnThisDayToday: Bool {
        onThisDayDate == MacOnThisDayDatePicker.day(of: Date())
    }

    /// "October 4 · 26 photos from 3 years" (board `MAC_OnThisDay`).
    private func onThisDayLine(_ library: LibraryModel) -> String {
        let day = onThisDayDate.formatted(.dateTime.month(.wide).day())
        guard !library.items.isEmpty else { return day }
        // A search here narrows the day: say so with the Library's own words.
        if library.hasActiveQuery {
            return day + " · " + LibraryCountLine.text(shown: library.items.count, videos: library.videoCount, total: nil, isFiltered: true)
        }
        guard onThisDayYears > 0 else {
            return day + " · " + String(AttributedString(localized: "^[\(library.items.count) photo](inflect: true)",
                                                         comment: "Mac On This Day subtitle before the years are counted").characters)
        }
        let words = AttributedString(localized: "^[\(library.items.count) photo](inflect: true) from ^[\(onThisDayYears) year](inflect: true)",
                                     comment: "Mac On This Day subtitle: 26 photos from 3 years")
        return day + " · " + String(words.characters)
    }

    /// What narrows the grid as rules: the Advanced Filter, or the quick
    /// filters converted — the starting point of Advanced Filter… and of
    /// Save as Smart Album….
    /// The suggestions under the search field (board `MAC_Search`).
    private var searchSuggestions: some View {
        MacSearchSuggestions(text: searchText, cameras: searchCameras, lenses: searchLenses, smartAlbums: smartAlbums,
                             recents: dependencies.search.recentSearches.queries, reading: searchReading,
                             openSmartAlbum: { album in
                                 searchText = ""
                                 setScope(.all)
                                 selection = .smartAlbum(album.id)
                             },
                             search: { runSearch($0) },
                             advancedSearch: { showsAdvancedFilter = true })
    }

    private func setScope(_ scope: MacSearchScope) {
        searchScope = scope
        library?.sourceScope = scope.query(sources: sources)
    }

    /// A suggestion picked: the field shows it and the grid is searched.
    private func runSearch(_ text: String) {
        searchText = text
        searchOwnsQuery = true
        library?.applySearch(text, using: dependencies.search)
    }

    /// The scope fits in a saved album: one source, and an "all of" search.
    private var canSaveSearch: Bool {
        guard let scope = library?.sourceScope else { return true }
        return scope.rules.count == 1 && (libraryQuery?.matchMode ?? .all) == .all
    }

    /// Save as Smart Album… from the scope bar: the search, and the scope
    /// when it is one source (an "any of several" scope does not nest in an
    /// "all of" album).
    private var savedSearchQuery: SmartAlbumQuery? {
        var query = libraryQuery ?? SmartAlbumQuery(matchMode: .all, rules: [])
        if let scope = library?.sourceScope, scope.rules.count == 1, query.matchMode == .all {
            query.rules += scope.rules
        }
        return query.rules.isEmpty ? nil : query
    }

    private var libraryQuery: SmartAlbumQuery? {
        guard let library else { return nil }
        if let advanced = library.advancedQuery, !advanced.isEmpty { return advanced }
        return library.criteria.isEmpty ? nil : .migrating(library.criteria)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { } label: { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                .disabled(true)
            Button { } label: { Label(String(localized: "Forward", comment: "Mac toolbar"), systemImage: "chevron.right") }
                .disabled(true)
        }
        if selection == .onThisDay {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsDatePicker.toggle() } label: {
                    Label(String(localized: "Choose Date", comment: "Mac On This Day toolbar"), systemImage: "calendar")
                }
                .help(String(localized: "Choose Date…", comment: "Mac On This Day toolbar"))
                .popover(isPresented: $showsDatePicker, arrowEdge: .bottom) {
                    MacOnThisDayDatePicker(date: $onThisDayDate)
                }
                Button { } label: {
                    Label(String(localized: "Play Slideshow", comment: "Mac toolbar"), systemImage: "play")
                }
                .disabled(true)
                .help(String(localized: "Play Slideshow", comment: "Mac toolbar"))
            }
        }
        if selection != .onThisDay {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(selection: $viewMode) {
                    Label(String(localized: "Grid", comment: "Mac toolbar view mode"), systemImage: "square.grid.2x2").tag(MacViewMode.grid)
                    Label(String(localized: "List", comment: "Mac toolbar view mode"), systemImage: "list.bullet").tag(MacViewMode.list)
                } label: {
                    Text("View", comment: "Mac toolbar view mode picker")
                }
                .pickerStyle(.segmented)
                .disabled(isLibraryEmpty)
                Button { showsFilterPopover.toggle() } label: {
                    // Filled while something narrows the grid, as in Photos.
                    // One symbol, its variant switched: a new image would rebuild
                    // the item and close a popover open on it.
                    Label(String(localized: "Filter and Sort", comment: "Mac toolbar"), systemImage: "line.3.horizontal.decrease.circle")
                        .symbolVariant(library?.hasActiveQuery == true ? .fill : .none)
                }
                .help(String(localized: "Filter and Sort", comment: "Mac toolbar"))
                .disabled(isLibraryEmpty)
                .popover(isPresented: $showsFilterPopover, arrowEdge: .bottom) {
                    if let library {
                        MacFilterPopover(library: library, countLine: subtitle,
                                         advancedFilter: {
                                             showsFilterPopover = false
                                             showsAdvancedFilter = true
                                         },
                                         saveAsSmartAlbum: {
                                             showsFilterPopover = false
                                             smartAlbumForm = MacSmartAlbumFormRequest(query: libraryQuery)
                                         })
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // Share the selection's files (Photos versions written out first).
            Menu {
                ForEach(MacPhotoMenu.shareServices, id: \.title) { service in
                    Button(service.menuItemTitle) { photoMenu?.share(photoSelection?.ids ?? [], with: service) }
                }
            } label: {
                Label(String(localized: "Share", comment: "Mac toolbar"), systemImage: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .help(photoSelection?.ids.isEmpty != false ? String(localized: "Select photos to share", comment: "Mac toolbar: Share is off with nothing selected")
                                                       : String(localized: "Share", comment: "Mac toolbar"))
            .disabled(isLibraryEmpty || photoSelection?.ids.isEmpty != false)
            // The label says what a click does (FS-18.01 §3).
            Button { showsInspector.toggle() } label: {
                Label(showsInspector ? String(localized: "Hide Inspector", comment: "Mac toolbar")
                                     : String(localized: "Show Inspector", comment: "Mac toolbar"),
                      systemImage: "sidebar.right")
            }
        }
    }

    private func start() async {
        // One model for every Library window, so a window reopened during a
        // run shows that run and Settings reads the same progress.
        if library == nil { library = dependencies.library ?? LibraryModel(dependencies: dependencies) }
        dependencies.library = library
        if photoMenu == nil { photoMenu = MacPhotoMenu(dependencies: dependencies) }
        if photoSelection == nil { photoSelection = MacSelectionModel(database: dependencies.database) }
        Task { await dependencies.photoMarks.loadIfNeeded() }
        #if DEBUG
        if MacDemoLibrary.section == "backup" { selection = .backup }
        if MacDemoLibrary.section == "onThisDay" { selection = .onThisDay }
        if MacDemoLibrary.section == "addServer" { serverForm = MacServerFormRequest() }
        if MacDemoLibrary.section == "addSource" { showsAddSource = true }
        // `sourceIndexing` needs `-ShotDexDemoSources`: the read and the offline drive.
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
            // `-ShotDexDemoSources`: the folder sources in the sidebar too.
            await MacDemoSources.seedIfAsked(dependencies)
            reloadSources()
            MacDemoLibrary.seedScaleIfAsked(dependencies) { library?.reload() }
            // `-ShotDexPerfCycle`: switch list/grid and sort by itself, then
            // quit — the hang watchdog's numbers without XCTest reading the
            // accessibility tree on the main thread at the same time.
            if ProcessInfo.processInfo.arguments.contains("-ShotDexPerfCycle") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    viewMode = ProcessInfo.processInfo.arguments.contains("-ShotDexPerfGrid") ? .grid : .list
                    try? await Task.sleep(for: .seconds(3))
                    for step in 0..<6 {
                        MacAgentProbe.log.notice("perf cycle: sort \(step, privacy: .public)")
                        library?.sort = step.isMultiple(of: 2) ? .isoDescending : .isoAscending
                        try? await Task.sleep(for: .seconds(2))
                    }
                    for step in 0..<4 {
                        MacAgentProbe.log.notice("perf cycle: mode \(step, privacy: .public)")
                        viewMode = step.isMultiple(of: 2) ? .grid : .list
                        try? await Task.sleep(for: .seconds(2))
                    }
                    MacAgentProbe.log.notice("perf cycle: done")
                    NSApp.terminate(nil)
                }
            }
            // `filterPopover` (default), `filterSet` (conditions + popover),
            // `filterBar` (conditions, popover closed) — board `MAC_FilterPopover`;
            // `filterSet` wants `-ShotDexOriginalCheck checked` for its Storage row.
            // `filterAdvanced`: the same conditions as an Advanced Filter.
            if let section = MacDemoLibrary.section, ["filterPopover", "filterSet", "filterBar", "filterAdvanced"].contains(section) {
                try? await Task.sleep(for: .seconds(1))
                if section != "filterPopover" {
                    var criteria = FilterCriteria()
                    criteria.cameraBodies = ["EOS R6m2"]
                    criteria.isoRange = NumericRangeFilter(lowerBound: 400, upperBound: 3200)
                    criteria.apertureRange = NumericRangeFilter(lowerBound: 1.2, upperBound: 2)
                    criteria.originalOnDeviceOnly = true
                    if section == "filterAdvanced" {
                        library?.advancedQuery = .migrating(criteria)
                    } else {
                        library?.criteria = criteria
                    }
                }
                showsFilterPopover = section != "filterBar"
            }
            return
        }
        #endif
        // A read paused before the last quit comes back paused (FS-19.01 §4).
        dependencies.sourcesModel.restorePausedRead()
        // The Photos permission is asked by Add Photos Library…, never here
        // (FS-18.01 §7): until then the window is the first-run screen.
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
        guard let library else { return }
        // A folder, drive or server is enough for a grid; the Photos index
        // needs the permission.
        if !isLibraryEmpty { library.loadIfNeeded() }
        guard dependencies.photoLibrary.authorizationState.canReadLibrary else { return }
        library.loadIfNeeded()
        library.startIndexing()
    }
}

enum MacViewMode: String, Hashable { case grid, list }

/// A Locate… pick that does not look like the source (FS-19.01b §2).
struct MacUnlikelyLocate {
    let row: SourcesModel.Row
    let folder: URL
    let found: Int
    let checked: Int
}

/// What Add a Source asked for (board `MAC_AddSource`).
enum MacAddSourceRequest {
    case photos
    case folder(URL, includesSubfolders: Bool, pairsRawAndJpeg: Bool)
    case server
}

/// New Smart Album… or editing one.
struct MacSmartAlbumFormRequest: Identifiable {
    let id = UUID()
    var editing: SmartAlbum?
    /// A new album's conditions: the Library's, from Save as Smart Album….
    var query: SmartAlbumQuery?
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

private struct MacRootRequests: ViewModifier {
    let root: MacRootWindow
    func body(content: Content) -> some View { root.requests(content) }
}

/// Calls back when this view's window becomes the key window.
private struct MacKeyWindowObserver: NSViewRepresentable {
    let becameKey: () -> Void

    func makeNSView(context: Context) -> NSView { Probe(becameKey: becameKey) }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? Probe)?.becameKey = becameKey }

    final class Probe: NSView {
        var becameKey: () -> Void
        private var token: NSObjectProtocol?

        init(becameKey: @escaping () -> Void) {
            self.becameKey = becameKey
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            token.map(NotificationCenter.default.removeObserver)
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameKey() }
            }
        }
    }
}

/// On This Day's Choose Date… (FS-06.07 §4): a month calendar and Today;
/// only the month and day are matched, so any year's calendar works.
struct MacOnThisDayDatePicker: View {
    @Binding var date: Date

    /// The calendar is 2024's, a leap year: every month and day, Feb 29
    /// included, and the year is never the point.
    static let leapYear = 2024

    static func day(of date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return calendar.date(from: DateComponents(year: leapYear, month: parts.month, day: parts.day)) ?? date
    }

    private static let range: ClosedRange<Date> = {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: leapYear, month: 1, day: 1))!
            ... calendar.date(from: DateComponents(year: leapYear, month: 12, day: 31))!
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(String(localized: "Day", comment: "Mac On This Day: the date picker"), selection: $date, in: Self.range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                // The chosen day in ShotDex amber, not system blue (MAC_STYLE).
                .tint(.accentColor)
            HStack {
                Spacer()
                Button(String(localized: "Today", comment: "Mac On This Day: back to today")) { date = Self.day(of: Date()) }
                    .disabled(date == Self.day(of: Date()))
            }
        }
        .padding(12)
        .fixedSize()
    }
}
