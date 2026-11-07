import Foundation
import Observation

/// The Mac's composition root (FS-18 T1): the shared data layer, built once
/// in `ShotDexMacApp`. It provides `LibraryServices`, so the Library grid
/// runs on the same `LibraryModel` as iOS. The iOS `AppDependencies` is not
/// reused whole — it builds ~30 iOS-only services (background tasks,
/// widgets, Spotlight) the Mac does not have.
@MainActor
@Observable
final class MacDependencies: LibraryServices {
    let database: AppDatabase
    let metadataStore: MetadataStore
    let libraryQueries: LibraryQueries
    let filterSuggestions: FilterSuggestionCache
    /// Typed queries to grid state (FS-18.02 §4): the parser, then free
    /// text. AI search is a later version on the Mac (FS-18.04 §3).
    let search: SearchService
    let indexPipeline: IndexPipeline
    let placeIndexPass: PlaceIndexPass
    /// Photos' captions and keywords mirrored into the index (FS-02.07 §8),
    /// macOS 27; nil in the demo, which reads no Photos library.
    let keywordMirror: ExtendedMetadataMirrorPass?
    /// Keyword writes to Photos (FS-02.07 §4); nil where the mirror is.
    let captionKeywords: CaptionKeywordService?
    /// File photos' stars and keywords on their way to the sidecars.
    let sidecarQueue: SidecarWriteQueue
    let unsupportedRAWIndex: UnsupportedRAWIndex
    let indexRunAssertion: any IndexRunAssertion = MacIndexActivity()
    let photoLibrary: PhotoLibraryService
    /// Stars and flags (FS-01.12): file photos' go to their sidecars, Photos'
    /// into Photos itself (macOS 27 keeps stars there).
    let photoMarks: PhotoMarks
    let networkStatus: NetworkMonitor
    let powerStatus: PowerMonitor
    let indexTraffic: IndexTrafficMonitor
    /// Index results shared over iCloud; nil in the demo library.
    let indexShare: IndexShareService?
    let sources: SourceStore
    /// The Library window's model, for Settings › Sources › Index to read
    /// progress from; nil until the window has opened.
    var library: LibraryModel?
    let fileServers: FileServerStore
    let folderRoots: FolderSourceRoots
    /// One server call at a time per connection for Backup and the On Server
    /// check (FS-19.07 §5).
    let connectionLock: ConnectionLock
    /// Backup jobs and their ledger (FS-22).
    let backups: BackupStore
    /// Runs the jobs while the app is open — until the login-item helper
    /// takes them over (FS-22.06 §2).
    let backupCoordinator: BackupCoordinator
    /// Sends job commands to the helper, or to `backupCoordinator` when the
    /// app runs the jobs itself (FS-22.06 §2).
    let backupControl: MacBackupControl
    let folderSources: FolderSourceRunner
    let serverSources: ServerSourceRefresh
    /// Sources in the sidebar: adding a server source, rescans (FS-19).
    let sourcesModel: SourcesModel
    /// Whether each Photos item has a byte-identical copy on a server
    /// source (FS-19.07, §11 for the Mac).
    let onServerCheck: OnServerCheck
    /// Which Photos items have every original on this Mac (FS-06.10). The
    /// app runs it while it is in front; the helper never starts it.
    let originalPresenceCheck: OriginalPresenceCheck
    /// Asks the server again before a Photos item that relies on it is
    /// deleted (FS-19.07 §9).
    let photoDeletionGate: PhotoDeletionGate
    let smartAlbums: SmartAlbumStore
    /// Find Common Photos runs (FS-19.08 §6): the run window and Activity
    /// read their progress here.
    let commonPhotos: MacCommonPhotosRuns
    /// Keep gathering's passes (FS-19.08 §6c), in the helper — or here while
    /// the helper does not run jobs.
    let gatherer: MacCommonPhotosGatherer
    /// The Compare window's row and scan (FS-19.08 §6d), set by the sheet
    /// that opens it.
    var commonPhotosCompare: MacCommonPhotosCompareModel?

    /// `originalCheck`: the demo library's stand-in for the PhotoKit probe;
    /// nil everywhere else.
    init(database: AppDatabase, photoLibrary: PhotoLibraryService, sharesIndex: Bool = false,
         originalCheck: OriginalPresenceCheck.Environment? = nil, watchesOriginals: Bool = true) {
        self.database = database
        self.photoLibrary = photoLibrary
        metadataStore = MetadataStore(database: database)
        let indexTraffic = IndexTrafficMonitor()
        self.indexTraffic = indexTraffic
        let indexShare = sharesIndex ? IndexShareService(store: SharedIndexStore(database: database)) : nil
        self.indexShare = indexShare
        indexPipeline = IndexPipeline(
            metadataStore: MetadataStore(database: database),
            exifReader: ExifReader(trafficMonitor: indexTraffic),
            interactionGate: IndexInteractionGate(),
            sharedIndex: indexShare,
            readsOriginalsOnly: { IndexReadPolicy.readsOriginalsOnly }
        )
        let libraryQueries = LibraryQueries(database: database)
        self.libraryQueries = libraryQueries
        filterSuggestions = FilterSuggestionCache(libraryQueries: libraryQueries)
        search = SearchService(filterSuggestions: filterSuggestions, recentSearches: RecentSearchStore())
        let placeStore = PlaceStore(database: database)
        placeIndexPass = PlaceIndexPass(store: placeStore, geocoder: PlaceGeocodingService(store: placeStore))
        unsupportedRAWIndex = UnsupportedRAWIndex(store: RAWVerdictStore(database: database))
        networkStatus = NetworkMonitor()
        powerStatus = PowerMonitor()
        sources = SourceStore(database: database)
        let fileServers = FileServerStore(database: database, passwords: KeychainPasswordStore())
        self.fileServers = fileServers
        let folderRoots = FolderSourceRoots(database: database)
        self.folderRoots = folderRoots
        let connectionLock = ConnectionLock()
        self.connectionLock = connectionLock
        let backups = BackupStore(database: database)
        self.backups = backups
        backupCoordinator = BackupCoordinator(store: backups, environment: .live(
            database: database, store: backups, servers: fileServers, roots: folderRoots, connectionLock: connectionLock
        ))
        let folderSources = FolderSourceRunner(database: database, metadataStore: metadataStore)
        self.folderSources = folderSources
        let serverSources = ServerSourceRefresh(database: database, servers: fileServers,
                                                composer: MetadataComposer(sensorLookup: SensorLookup(
                                                    records: (try? SensorDatabaseLoader().loadRecords()) ?? [],
                                                    customMappings: (try? metadataStore.customMappings()) ?? [])),
                                                thumbnails: .standard,
                                                makeClient: { server, password in
                                                    LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: password),
                                                                           lock: connectionLock, connectionId: server.id, priority: .normal)
                                                })
        self.serverSources = serverSources
        let sourcesModel = SourcesModel(database: database, runner: folderSources, servers: serverSources, photoLibrary: photoLibrary)
        // Thumbnails written since the last launch may have passed Cache Size
        // Limit (AC-76): held to it once per launch, off the main actor.
        Task.detached(priority: .background) {
            PreviewCacheStore.standard.trim(to: PreviewCachePolicy.bytes(gigabytes: PreviewCachePolicy.limit()))
        }
        self.sourcesModel = sourcesModel
        let sidecarQueue = SidecarWriteQueue(writer: SidecarWriter(database: database) { sourceId, path in
            folderRoots.fileURL(sourceId: sourceId, relativePath: path)
        })
        self.sidecarQueue = sidecarQueue
        var ratingWriter: (any PhotoPropertyWriting)?
        if #available(macOS 27, *) { ratingWriter = PhotoKitPropertyWriter() }
        #if DEBUG
        // The demo's photos have no assets: their stars wait in the pending
        // table, where the list reads them.
        if MacDemoLibrary.isOn { ratingWriter = nil }
        #endif
        photoMarks = PhotoMarks(
            store: PhotoMarksStore(database: database),
            metadataStore: metadataStore,
            ratingWriter: ratingWriter,
            readPhotosRatings: { @Sendable ids in
                PhotoLibraryService.fetchAssets(ids: ids).reduce(into: [:]) { result, asset in
                    if let rating = asset.photosStarRating { result[asset.localIdentifier] = rating }
                }
            },
            sidecarQueue: sidecarQueue
        )
        var keywordReader: (any ExtendedMetadataReading)?
        if #available(macOS 27, *) { keywordReader = PhotoKitExtendedMetadataReader() }
        #if DEBUG
        if MacDemoLibrary.isOn { keywordReader = nil }
        #endif
        // One process mirrors Photos' keywords: the window, not the helper,
        // which shares the database and would interleave the same rows.
        if !watchesOriginals { keywordReader = nil }
        if let keywordReader, let ratingWriter {
            let keywordStore = PhotoKeywordStore(database: database)
            let mirror = ExtendedMetadataMirrorPass(store: keywordStore, reader: keywordReader, shouldPause: { false })
            indexPipeline.runObservers.add { changes in await mirror.handle(changes) }
            keywordMirror = mirror
            let filterSuggestions = filterSuggestions
            captionKeywords = CaptionKeywordService(
                writer: ratingWriter, reader: keywordReader, mirror: mirror, store: keywordStore, metadataStore: metadataStore,
                keywordCatalog: { recount in
                    recount ? await filterSuggestions.refreshKeywords() : await filterSuggestions.load().keywords
                })
        } else {
            keywordMirror = nil
            captionKeywords = nil
        }
        onServerCheck = OnServerCheck(environment: .live(
            database: database, servers: fileServers, refresh: serverSources, connectionLock: connectionLock,
            // FS-19.07 §12.1: the Mac hashes everything for the other devices
            // while it shares the index.
            hashesEverything: { [hasIndexShare = indexShare != nil] in hasIndexShare && IndexShareService.sharesIndex },
            indexShare: indexShare,
            listingChanged: { await sourcesModel.serverListingChanged() }
        ))
        backupControl = MacBackupControl(coordinator: backupCoordinator, photoLibrary: photoLibrary,
                                         onServerCheck: onServerCheck, database: database)
        #if DEBUG
        OnServerMismatchDemo.seed(database: database, servers: fileServers, check: onServerCheck)
        #endif
        let originalPresenceCheck = OriginalPresenceCheck(environment: originalCheck ?? .live(database: database, gate: nil))
        self.originalPresenceCheck = originalPresenceCheck
        // The app's own: the login-item helper never runs the check, so it
        // must not write its tables behind the app's back either.
        if watchesOriginals {
            photoLibrary.onAssetsChanged = { ids in Task { await originalPresenceCheck.assetsChanged(ids) } }
        }
        photoDeletionGate = PhotoDeletionGate(
            database: database,
            connect: { connectionId in
                guard let server = try? fileServers.fetch(id: connectionId) else { return nil }
                let client = LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: fileServers.password(for: server.id) ?? ""),
                                                    lock: connectionLock, connectionId: server.id, priority: .normal)
                return (client, server.folder)
            },
            relist: { sourceId in _ = await serverSources.rescan(sourceId: sourceId) }
        )
        photoLibrary.deletionGate = photoDeletionGate
        smartAlbums = SmartAlbumStore(database: database)
        commonPhotos = MacCommonPhotosRuns(database: database, servers: fileServers, refresh: serverSources) { server in
            LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: fileServers.password(for: server.id) ?? ""),
                                   lock: connectionLock, connectionId: server.id, priority: .normal)
        }
        gatherer = MacCommonPhotosGatherer(database: database, servers: fileServers, runs: commonPhotos) { server in
            LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: fileServers.password(for: server.id) ?? ""),
                                   lock: connectionLock, connectionId: server.id, priority: .normal)
        }
    }

    private var gathersInApp = false

    /// The app's side of Keep gathering (FS-19.08 §6c), once: its own
    /// passes while the helper does not run jobs, and what the helper
    /// changed read again. Never in the helper, which starts its own.
    func startGatheringInApp() {
        guard !gathersInApp else { return }
        gathersInApp = true
        let runs = commonPhotos
        gatherer.isOn = { !MacAgentLink.agentRunsJobs }
        #if DEBUG
        // The demo library's database is not the helper's: the app gathers.
        if MacDemoLibrary.isOn { gatherer.isOn = { true } }
        #endif
        gatherer.onChange = { runs.storeChanged() }
        MacAgentLink.observe(MacAgentLink.commonPhotosChanged) { runs.storeChanged() }
        gatherer.start()
    }

    /// Run Now (Activity): the helper's pass when it runs jobs, else ours.
    func gatherNow(watchId: String) {
        if MacAgentLink.agentRunsJobs {
            MacAgentLink.post(.init(action: .gatherNow, jobId: watchId))
        } else {
            gatherer.gatherNow(watchId: watchId)
        }
    }

    /// A set was turned on or off: the helper starts for it, or re-reads.
    func watchesChanged() {
        #if DEBUG
        // The demo database is not the helper's: never register it for one.
        if MacDemoLibrary.isOn { return }
        #endif
        MacAgentLink.ensureAgent(hasWork: MacCommonPhotosGatherer.hasWork(database))
        MacAgentLink.post(.init(action: .watchesChanged, jobId: nil))
    }

    /// A client for `server` whose every call waits its turn on the
    /// connection's lock (FS-19.07 §5) — what anything browsing a
    /// connection uses, never a bare `RemoteFileClientFactory.make`.
    func lockedClient(for server: FileServer, priority: ConnectionLock.Priority = .normal) -> any RemoteFileClient {
        LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: fileServers.password(for: server.id) ?? ""),
                               lock: connectionLock, connectionId: server.id, priority: priority)
    }

    /// Move / Delete / Hide across sources (FS-19.04), as on iOS: Photos
    /// through PhotoKit's dialog, files to the Trash of their volume, NAS
    /// copies hidden — never deleted on the server.
    /// Hide, Hide in Photos and Hide in ShotDex Only (FS-19.04 §3). The
    /// demo's photos are rows: it never asks Photos to hide anything.
    var hideService: HideService {
        let photoLibrary = photoLibrary
        #if DEBUG
        if MacDemoLibrary.isOn { return HideService(database: database) { _ in } }
        #endif
        return HideService(database: database) { ids in
            try await photoLibrary.setHidden(true, for: PhotoLibraryService.fetchAssets(ids: ids))
        }
    }

    /// "Moved 1 file to the Trash. Hid 1 photo on NAS Home." — the front
    /// window shows it for a few seconds (`MacToast`).
    static let showToast: (String) -> Void = { text in
        NotificationCenter.default.post(name: .macToast, object: text)
    }

    var sourceDeletion: SourceDeletionContext {
        let database = database
        let photoLibrary = photoLibrary
        let roots = folderRoots
        #if DEBUG
        // The demo's copies are rows: nothing is trashed, removed or deleted
        // in Photos — the run only writes what it would have done.
        if MacDemoLibrary.isOn {
            return SourceDeletionContext(
                makeService: {
                    var service = DeletionService(database: database, deletePhotosAssets: { _ in },
                                                  root: { _ in FileManager.default.temporaryDirectory })
                    service.trash = { _ in }
                    service.remove = { _ in }
                    return service
                },
                makeQueries: { DeletionTargetQueries(database: database, hasTrash: { _ in true }) },
                showBanner: Self.showToast
            )
        }
        #endif
        return SourceDeletionContext(
            makeService: {
                DeletionService(
                    database: database,
                    deletePhotosAssets: { ids in try await photoLibrary.deleteAssetsCheckingServer(PhotoLibraryService.fetchAssets(ids: ids)) },
                    root: { roots.root($0) }
                )
            },
            makeQueries: { DeletionTargetQueries(database: database, hasTrash: { roots.hasTrash($0) }) },
            showBanner: Self.showToast
        )
    }

    /// `inHelper`: the login-item helper's copy, which leaves the
    /// original check alone (FS-06.10).
    static func live(inHelper: Bool = false) -> MacDependencies {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            assertionFailure("Failed to open database: \(error)")
            database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        }
        return MacDependencies(database: database, photoLibrary: PhotoLibraryService(), sharesIndex: true,
                               watchesOriginals: !inHelper)
    }
}

/// An index run on the Mac: an activity that keeps App Nap from throttling
/// it while the window is in the background. Nothing expires it.
@MainActor
final class MacIndexActivity: IndexRunAssertion {
    private var activity: NSObjectProtocol?

    func beginRunAssertion(onExpiry: @escaping @MainActor () -> Void) {
        guard activity == nil else { return }
        // App Nap never throttles a run; the Mac stays awake for it only when
        // Settings › Sources › Prevent Sleep While Indexing is on.
        // On unless turned off (an overnight index of a whole library should finish).
        let preventsSleep = UserDefaults.standard.object(forKey: SettingsKeys.preventsSleepWhileIndexing) as? Bool ?? true
        activity = ProcessInfo.processInfo.beginActivity(options: preventsSleep ? .userInitiated : .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Indexing the photo library")
    }

    func endRunAssertion() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
