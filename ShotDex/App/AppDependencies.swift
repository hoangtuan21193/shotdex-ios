import Foundation
import SwiftUI
import ShotDexKit

/// Composition root. Built once at launch and injected through the environment.
@MainActor
@Observable
final class AppDependencies {
    let database: AppDatabase
    let metadataStore: MetadataStore
    let libraryQueries: LibraryQueries
    let filterSuggestions: FilterSuggestionCache
    let statisticsQueries: StatisticsQueries
    let smartAlbumStore: SmartAlbumStore
    let creations: CreationStore
    let chartStore: ChartStore
    let photoLibrary: PhotoLibraryService
    let photoRenderer: PhotoRenderService
    let photoEditing: PhotoEditingService
    let compressionPresets: CompressionPresetStore
    let signaturePresets: SignaturePresetStore
    let overlayFontRecents: OverlayFontRecentsStore
    let collagePresets: CollagePresetStore
    let overlayImages: OverlayImageStore
    let videoStudio: VideoStudioService
    /// Joins overlapping frames into one photo (FS-14).
    let panoramaStitchService: PanoramaStitchService
    let indexPipeline: IndexPipeline
    let backgroundIndex: BackgroundIndexService
    let networkStatus: NetworkMonitor
    let powerStatus: PowerMonitor
    let indexTraffic: IndexTrafficMonitor
    let indexInteractionGate: IndexInteractionGate
    let placeStore: PlaceStore
    let placeGeocoding: PlaceGeocodingService
    let placeIndexPass: PlaceIndexPass
    let recentSearches: RecentSearchStore
    let searchService: SearchService
    let onThisDayNotifications: OnThisDayNotificationService
    let perceptualHashStore: PerceptualHashStore
    let duplicateScanPipeline: DuplicateScanPipeline
    /// The opt-in people-and-pets pass. Never started by the app itself —
    /// see `SubjectScanPipeline`.
    let subjectScan: SubjectScanModel
    /// Favorite / hide / capture-date / location / copy actions and the
    /// sheets they raise, for anything outside a window's own root — the
    /// detail viewer's sibling below, and previews.
    ///
    /// **A window's root builds its own** with `makeAssetActions()`: the
    /// coordinator carries presentation state, and one instance hosted by two
    /// windows means an Adjust Date sheet raised in one of them is bound to
    /// state the other is also hosting.
    let assetActions: AssetActionsCoordinator
    /// A second, independent coordinator for the detail viewer.
    ///
    /// It cannot share `assetActions`: the viewer is a `fullScreenCover`, and
    /// two hosts bound to the same presentation state both try to present —
    /// the root's sheet wins by tearing the cover down. Only one viewer exists
    /// at a time, so one extra instance covers it.
    let viewerAssetActions: AssetActionsCoordinator
    /// A coordinator of its own for one window's root. See `assetActions`.
    func makeAssetActions() -> AssetActionsCoordinator {
        AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity
        )
    }

    /// Publishes the library's collections (smart albums, cameras, lenses) to
    /// Spotlight. Individual photos are never indexed — see the type's note.
    let spotlight: SpotlightIndexer
    /// Collections the user pinned to the top of the Collections tab.
    let collectionPins: CollectionPinStore
    /// Copied edits, carried between photos and across launches.
    let editClipboard: EditClipboard
    /// The user's own saved looks, beside the fixed film looks.
    let lookPresets: LookPresetStore
    /// `.cube` LUTs imported from Files — one list for the photo editor's
    /// Presets and Video Studio's colour panel.
    let importedLUTs: ImportedLUTStore
    /// The order and visibility of the Collections tab's sections.
    let collectionsLayout: CollectionsLayoutStore
    /// Photos opened and photos shared, for the Recently Viewed / Recently
    /// Shared collections. PhotoKit records neither.
    let recentActivity: RecentActivityStore
    /// What the photo widgets (Clock, Calendar, Weather, Combined) show and
    /// how they are styled, edited in Settings and stored in the App Group the
    /// widgets read.
    let photoWidgetSettings: PhotoWidgetSettingsStore
    /// Today's events for the calendar widgets; owns the EventKit store.
    let calendarWidgetWriter: CalendarSnapshotWriter
    /// One coarse fix for the weather widgets, asked for only when one is
    /// placed.
    let widgetLocation: WidgetLocationProvider
    /// Bug reports and feature requests, anonymous and app-only. Apple offers
    /// no user-to-developer channel, so this is it.
    let support: SupportService
    /// The SMB/SFTP servers originals are uploaded to (FS-15.01).
    let fileServers: FileServerStore
    /// Which files are verified on a server (FS-15.02 §8).
    let serverUploads: ServerUploadStore
    /// The set of uploaded asset ids the grid badge reads, kept in memory.
    let serverUploadIndex: ServerUploadIndex

    init(database: AppDatabase, photoLibrary: PhotoLibraryService) {
        let metadataStore = MetadataStore(database: database)
        let indexTraffic = IndexTrafficMonitor()
        let indexInteractionGate = IndexInteractionGate()
        let indexPipeline = IndexPipeline(
            metadataStore: MetadataStore(database: database),
            exifReader: ExifReader(trafficMonitor: indexTraffic),
            interactionGate: indexInteractionGate
        )
        self.database = database
        self.metadataStore = metadataStore
        let libraryQueries = LibraryQueries(database: database)
        self.libraryQueries = libraryQueries
        let filterSuggestions = FilterSuggestionCache(libraryQueries: libraryQueries)
        self.filterSuggestions = filterSuggestions
        self.statisticsQueries = StatisticsQueries(database: database)
        self.smartAlbumStore = SmartAlbumStore(database: database)
        self.creations = CreationStore(database: database)
        self.chartStore = ChartStore(database: database)
        self.photoLibrary = photoLibrary
        let photoRenderer = PhotoRenderService()
        self.photoRenderer = photoRenderer
        self.photoEditing = PhotoEditingService(
            renderer: photoRenderer,
            indexNewAsset: { assetID in
                _ = await indexPipeline.indexSingle(assetId: assetID)
            },
            publishCreatedAsset: { _ in
                photoLibrary.publishAppCreatedAsset()
            }
        )
        let placeStore = PlaceStore(database: database)
        let placeGeocoding = PlaceGeocodingService(store: placeStore)
        self.placeStore = placeStore
        self.placeGeocoding = placeGeocoding
        self.placeIndexPass = PlaceIndexPass(store: placeStore, geocoder: placeGeocoding)
        let recentSearches = RecentSearchStore()
        self.recentSearches = recentSearches
        self.searchService = SearchService(
            filterSuggestions: filterSuggestions,
            recentSearches: recentSearches
        )
        self.compressionPresets = CompressionPresetStore()
        let overlayImages = OverlayImageStore()
        self.overlayImages = overlayImages
        self.signaturePresets = SignaturePresetStore(images: overlayImages)
        self.overlayFontRecents = OverlayFontRecentsStore()
        self.collagePresets = CollagePresetStore()
        self.videoStudio = VideoStudioService(
            importFile: { url, isVideo in
                try await photoLibrary.importFile(at: url, isVideo: isVideo)
            },
            indexNewAsset: { assetID in
                _ = await indexPipeline.indexSingle(assetId: assetID)
            },
            publishCreatedAsset: {
                photoLibrary.publishAppCreatedAsset()
            }
        )
        self.panoramaStitchService = PanoramaStitchService.live(
            photoLibrary: photoLibrary,
            indexAsset: { assetID in
                _ = await indexPipeline.indexSingle(assetId: assetID)
                await MainActor.run { photoLibrary.publishAppCreatedAsset() }
            }
        )
        self.indexPipeline = indexPipeline
        let networkStatus = NetworkMonitor()
        self.networkStatus = networkStatus
        let onThisDayScheduler = OnThisDayNotificationScheduler(
            queries: OnThisDayQueries(database: database)
        )
        self.onThisDayNotifications = OnThisDayNotificationService(scheduler: onThisDayScheduler)
        // Same policy the foreground uses (`LibraryModel.allowNetworkForIndexing`):
        // an unmetered path always, a metered one only on explicit opt-in.
        self.backgroundIndex = BackgroundIndexService(
            pipeline: indexPipeline,
            metadataStore: metadataStore,
            allowNetwork: {
                !networkStatus.isExpensivePath
                    || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
            },
            notificationsEnabled: {
                UserDefaults.standard.bool(forKey: SettingsKeys.onThisDayNotificationsEnabled)
            },
            refreshNotifications: { await onThisDayScheduler.refresh() }
        )
        self.powerStatus = PowerMonitor()
        let perceptualHashStore = PerceptualHashStore(database: database)
        self.perceptualHashStore = perceptualHashStore
        self.duplicateScanPipeline = DuplicateScanPipeline(
            store: perceptualHashStore,
            reader: PerceptualHashReader()
        )
        self.indexTraffic = indexTraffic
        self.indexInteractionGate = indexInteractionGate
        let recentActivity = RecentActivityStore()
        self.recentActivity = recentActivity
        self.assetActions = AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity
        )
        self.viewerAssetActions = AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity
        )
        self.subjectScan = SubjectScanModel(
            pipeline: SubjectScanPipeline(
                store: metadataStore,
                reader: SubjectVisionReader()
            ),
            store: metadataStore,
            allowNetwork: {
                !networkStatus.isExpensivePath
                    || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
            }
        )
        self.collectionPins = CollectionPinStore()
        self.editClipboard = EditClipboard()
        self.lookPresets = LookPresetStore()
        self.importedLUTs = ImportedLUTStore()
        self.collectionsLayout = CollectionsLayoutStore()
        self.spotlight = SpotlightIndexer(
            libraryQueries: libraryQueries,
            smartAlbumStore: SmartAlbumStore(database: database)
        )
        self.photoWidgetSettings = PhotoWidgetSettingsStore(photoLibrary: photoLibrary)
        self.calendarWidgetWriter = CalendarSnapshotWriter()
        self.widgetLocation = WidgetLocationProvider()
        self.support = SupportService()
        self.fileServers = FileServerStore(database: database, passwords: KeychainPasswordStore())
        let serverUploads = ServerUploadStore(database: database)
        self.serverUploads = serverUploads
        self.serverUploadIndex = ServerUploadIndex(store: serverUploads)
    }

    /// Refreshes everything the Home and Lock Screen widgets read: the next
    /// few On This Day days, the photos behind the photo widgets, and — only
    /// when a widget that shows them is actually placed — today's calendar
    /// events and the weather. Called on launch and on every return to the
    /// foreground; a no-op when the App Group is not reachable, which is how a
    /// build without the capability behaves.
    ///
    /// Each writer decides for itself whether there is work: On This Day skips
    /// unless a day is missing or the library moved, the weather skips unless
    /// its last reading is half an hour old, and the calendar skips unless a
    /// widget lists events.
    func refreshWidgetSnapshot() async {
        // The widgets write these settings too, so whatever was chosen on the
        // Home Screen while the app was away is read back before anything acts
        // on the app's own copy.
        photoWidgetSettings.reloadFromDisk()
        guard photoLibrary.authorizationState.canReadLibrary else { return }
        await OnThisDaySnapshotWriter(photoLibrary: photoLibrary).write()
        // The Home Screen's own widget menu picks albums from this list, and
        // the widgets that were pointed at one there are waiting for its
        // photos to be copied across.
        await WidgetAlbumCatalogWriter().write()
        await WidgetPhotoCatalogWriter(photoLibrary: photoLibrary).write()
        let photoWidgetWriter = PhotoWidgetSnapshotWriter(photoLibrary: photoLibrary)
        await photoWidgetWriter.fulfilRequests()
        await photoWidgetWriter.refreshStaleFolders()
        await calendarWidgetWriter.write()
        await WeatherSnapshotWriter(location: widgetLocation).write()
    }

    /// Fills in the capture kind (screenshot, Live Photo, portrait, …) for
    /// rows written before that column existed.
    ///
    /// A backfill rather than a reindex: `PHAsset.mediaSubtypes` is already in
    /// memory once the asset is fetched, so this reads no files and touches no
    /// EXIF. Without it the capture-kind filter would match nothing until each
    /// photo happened to change and be re-read.
    func backfillMediaSubtypes() async {
        let store = metadataStore
        await Task.detached(priority: .utility) {
            // Batched so a very large library does not build one enormous
            // dictionary or hold one very long write transaction.
            while true {
                guard let ids = try? store.assetIdsMissingMediaSubtypes(limit: 2_000),
                      !ids.isEmpty
                else { return }
                var subtypes: [String: Int] = [:]
                for asset in PhotoLibraryService.fetchAssets(ids: ids) {
                    subtypes[asset.localIdentifier] = Int(asset.mediaSubtypes.rawValue)
                }
                // Ids PhotoKit no longer knows would otherwise be re-selected
                // for ever; record them as "no subtype" so the loop ends.
                for id in ids where subtypes[id] == nil {
                    subtypes[id] = 0
                }
                try? store.fillMediaSubtypes(subtypes)
                if ids.count < 2_000 { return }
            }
        }.value
    }

    /// Re-resolves cameras indexed as Unknown against the bundled sensor
    /// database — an app update that ships new records fixes already-indexed
    /// photos without a reindex. Cheap: touches only still-unknown models.
    func resolveNewlyKnownCameras() {
        let store = metadataStore
        Task.detached(priority: .utility) {
            guard let records = try? SensorDatabaseLoader().loadRecords() else { return }
            let mappings = (try? store.customMappings()) ?? []
            _ = try? store.resolveUnknownCameras(
                using: SensorLookup(records: records, customMappings: mappings)
            )
        }
    }

    static func live() -> AppDependencies {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            // A broken on-disk database would leave the app unusable;
            // fall back to an in-memory store so the UI can still surface the error.
            assertionFailure("Failed to open database: \(error)")
            database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        }
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService())
    }

    static func preview() -> AppDependencies {
        let database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService())
    }
}
