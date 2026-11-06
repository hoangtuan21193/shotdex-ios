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
    /// Add Photos Library… came back without access.
    @State private var showsPhotosDenied = false
    @State private var showsInspector = false
    @State private var showsBackupInspector = true
    /// File › New Backup… asked for the sheet; the Backup screen opens it.
    @State private var opensNewBackup = false
    @State private var serverForm: MacServerFormRequest?
    @State private var smartAlbumForm: MacSmartAlbumFormRequest?
    @State private var smartAlbums: [SmartAlbum] = []
    /// Why the sidebar's Add Folder… could not add (Settings shows its own).
    @State private var addFolderFailure: SourcesModel.Failure?
    @State private var viewMode = MacViewMode.grid
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

    var body: some View {
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
                library?.place = place(for: selection)
            }
        }
        // One LibraryModel serves every Library window: the key window's
        // place is the one it shows.
        .background(MacKeyWindowObserver { if let selection, isGridPlace(selection) { library?.place = place(for: selection) } })
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
        content
            .background(MacMainWindowMarker())
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
            .onReceive(NotificationCenter.default.publisher(for: .macAddFolder)) { _ in addFolderFromSidebar() }
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
    /// The sidebar, with what its + › Add Folder… could not add.
    private var sidebar: some View {
        // The first run counts nothing (board `MAC_EmptyLibrary`): no row of zeros.
        MacSidebar(selection: $selection, library: library, counts: isLibraryEmpty ? [:] : placeCounts,
                   sources: photosAdded ? sources : sources.filter { $0.kind != "photos" },
                   backup: backupBadge, smartAlbums: smartAlbums,
                   newSmartAlbum: { smartAlbumForm = MacSmartAlbumFormRequest() },
                   addFolder: addFolderFromSidebar,
                   addPhotosLibrary: photosAdded ? nil : addPhotosLibrary,
                   connectToServer: { serverForm = MacServerFormRequest() },
                   addFolders: addFolders,
                   busyFooter: dependencies.commonPhotos.footRunId.map { AnyView(MacCommonPhotosFoot(runId: $0)) })
            .navigationSplitViewColumnWidth(MacWindowMetrics.sidebarWidth)
            .alert(addFolderFailure?.title ?? "",
                   isPresented: Binding(get: { addFolderFailure != nil }, set: { if !$0 { addFolderFailure = nil } })) {
                Button(String(localized: "OK", comment: "Mac alert: dismiss")) {}
            } message: {
                Text(addFolderFailure?.message ?? "")
            }
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
    private func addFolders(_ urls: [URL]) {
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
                await model.addFolder(folder, includesSubfolders: true, pairsRawAndJpeg: true)
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
        case .allPhotos, .favorites, .videos, .raw, .recentlyAdded: true
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

    /// The sidebar's + › Add Folder…: what Settings › Sources adds, the
    /// failure said here rather than in a Settings window that may be shut.
    private func addFolderFromSidebar() {
        MacPhotoSourcesSection.chooseFolder { addFolders([$0]) }
    }

    /// Jobs, or a warning when one is stuck on something only the user can
    /// fix (FS-22.06 §5.1).
    private var backupBadge: (jobs: Int, needsAttention: Bool) {
        let coordinator = dependencies.backupCoordinator
        let stuck: Set<BackupJobState.Status> = [.unreachable, .destinationFull, .signInFailed, .noPhotosAccess]
        return (coordinator.jobs.count, coordinator.states.values.contains { stuck.contains($0.status) })
    }

    private var libraryDetail: some View {
            VStack(spacing: 0) {
                if let library, showsFilterBar, library.hasActiveQuery {
                    MacFilterBar(library: library)
                }
                content
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
                .onReceive(NotificationCenter.default.publisher(for: .macShowFilterPopover)) { _ in showsFilterPopover = true }
                .sheet(isPresented: $showsAdvancedFilter) {
                    MacSmartAlbumEditorSheet(initialQuery: libraryQuery,
                                             applyFilter: {
                                                 searchOwnsQuery = false
                                                 library?.advancedQuery = $0.isEmpty ? nil : $0
                                             })
                }
                .navigationTitle(placeTitle)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $searchText, placement: .toolbar,
                            prompt: isLibraryEmpty ? Text("Search", comment: "Mac search field placeholder before any photo")
                                                   : Text("Canon R6 85mm ISO 3200", comment: "Mac search field placeholder: a sample query"))
                .searchFocused($isSearchFocused)
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
                    if searchOwnsQuery { library.advancedQuery = nil }
                    searchOwnsQuery = false
                }
                .inspector(isPresented: $showsInspector) {
                    Text("Info", comment: "Mac inspector placeholder")
                        .foregroundStyle(.secondary)
                        .inspectorColumnWidth(MacWindowMetrics.inspectorWidth)
                }
    }

    @ViewBuilder
    private var content: some View {
        if isLibraryEmpty {
            MacEmptyLibrary(addPhotosLibrary: addPhotosLibrary, addFolder: addFolderFromSidebar,
                            connectToServer: { serverForm = MacServerFormRequest() }, addFolders: addFolders)
        } else if let library, !library.items.isEmpty {
            // Newest-first position i is the model's (bottom-anchored) count − 1 − i.
            MacPhotoGrid(items: library.items, photoLibrary: dependencies.photoLibrary, asset: { library.asset(for: $0) },
                         picture: Self.demoPicture, generation: library.rowsGeneration,
                         assetAt: { library.asset(atFlatIndex: library.items.count - 1 - $0) },
                         assetGeneration: library.contentRefreshGeneration)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let library, library.hasActiveQuery, !library.isLoading || settledMatchCount == 0 {
            ContentUnavailableView {
                Label(String(localized: "No Photos Match", comment: "Mac library: the filter leaves nothing"),
                      systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("No photo matches the current filters.", comment: "Mac library: empty filtered grid")
            } actions: {
                Button(MacFilterCopy.resetFilters) {
                    library.criteria = .empty
                    library.advancedQuery = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let library, !library.isLoading, library.items.isEmpty, !library.hasActiveQuery, library.place != nil {
            // A place with nothing in it says so; the spinner is only for loading.
            ContentUnavailableView(emptyPlaceTitle, systemImage: selection?.systemImage ?? "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let shown = library.hasActiveQuery && library.isLoading ? settledMatchCount ?? library.items.count : library.items.count
        return LibraryCountLine.text(shown: shown, videos: library.videoCount, total: libraryTotal,
                                     isFiltered: library.hasActiveQuery, libraryHasVideos: libraryHasVideos)
    }

    /// What narrows the grid as rules: the Advanced Filter, or the quick
    /// filters converted — the starting point of Advanced Filter… and of
    /// Save as Smart Album….
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button { } label: { Label(String(localized: "Share", comment: "Mac toolbar"), systemImage: "square.and.arrow.up") }
                .disabled(isLibraryEmpty)
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
            // `-ShotDexDemoSources`: the folder sources in the sidebar too.
            await MacDemoSources.seedIfAsked(dependencies)
            reloadSources()
            MacDemoLibrary.seedScaleIfAsked(dependencies) { library?.reload() }
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

enum MacViewMode: Hashable { case grid, list }

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
