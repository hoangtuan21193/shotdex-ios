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
    let indexPipeline: IndexPipeline
    let placeIndexPass: PlaceIndexPass
    let keywordMirror: ExtendedMetadataMirrorPass? = nil
    let unsupportedRAWIndex: UnsupportedRAWIndex
    let indexRunAssertion: any IndexRunAssertion = MacIndexActivity()
    let photoLibrary: PhotoLibraryService
    let networkStatus: NetworkMonitor
    let powerStatus: PowerMonitor
    let indexTraffic: IndexTrafficMonitor
    /// Index results shared over iCloud; nil in the demo library.
    let indexShare: IndexShareService?
    let sources: SourceStore
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

    init(database: AppDatabase, photoLibrary: PhotoLibraryService, sharesIndex: Bool = false) {
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
        self.sourcesModel = sourcesModel
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
    func lockedClient(for server: FileServer) -> any RemoteFileClient {
        LockedRemoteFileClient(RemoteFileClientFactory.make(for: server, password: fileServers.password(for: server.id) ?? ""),
                               lock: connectionLock, connectionId: server.id, priority: .normal)
    }

    static func live() -> MacDependencies {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            assertionFailure("Failed to open database: \(error)")
            database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        }
        return MacDependencies(database: database, photoLibrary: PhotoLibraryService(), sharesIndex: true)
    }
}

/// An index run on the Mac: an activity that keeps App Nap from throttling
/// it while the window is in the background. Nothing expires it.
@MainActor
final class MacIndexActivity: IndexRunAssertion {
    private var activity: NSObjectProtocol?

    func beginRunAssertion(onExpiry: @escaping @MainActor () -> Void) {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Indexing the photo library")
    }

    func endRunAssertion() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
