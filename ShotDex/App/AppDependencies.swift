import Foundation
import Photos
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
    /// Asks whether a photo's original is on the device, and downloads it
    /// (FS-02.06). Scripted under the DEBUG launch argument
    /// `-ShotDexFakeICloud`, because a simulator has no iCloud library.
    let originalFetcher: any OriginalFetching
    /// The Share modal every way into Share uses (FS-02.06 §9).
    let originalDownloads: OriginalDownloadModel
    let compressionPresets: CompressionPresetStore
    let signaturePresets: SignaturePresetStore
    /// The watermark the export forms remember and Watermark When Sharing
    /// (FS-05.04).
    let watermarkSettings: WatermarkSettingsStore
    /// What shares and drags stamp; the drag holds it weakly.
    let shareWatermark: ShareWatermarkContext
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
    /// Index results shared over iCloud; nil in previews and tests.
    let indexShare: IndexShareService?
    let indexInteractionGate: IndexInteractionGate
    let placeStore: PlaceStore
    let placeGeocoding: PlaceGeocodingService
    let placeIndexPass: PlaceIndexPass
    let recentSearches: RecentSearchStore
    let searchService: SearchService
    let onThisDayNotifications: OnThisDayNotificationService
    let perceptualHashStore: PerceptualHashStore
    let duplicateScanPipeline: DuplicateScanPipeline
    /// Scores grouped photos for Duplicates (FS-06.06 §6); yields to a
    /// person looking at a photo, like the index.
    let duplicateQualityPass: DuplicateQualityPass
    /// Marks and decisions on the Duplicates screen, kept on disk until the
    /// user deletes or undoes them (FS-06.06b §1).
    let duplicateReview: DuplicateReviewSession
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
    ///
    /// So screens never call this one: they read `\.assetActions`, which
    /// `.assetActionHost(_:)` sets to the coordinator it hosts. Sending an
    /// action here from a grid raises a sheet no host presents.
    let assetActions: AssetActionsCoordinator
    /// A second, independent coordinator for the detail viewer.
    ///
    /// It cannot share `assetActions`: the viewer is a `fullScreenCover`, and
    /// two hosts bound to the same presentation state both try to present —
    /// the root's sheet wins by tearing the cover down. Only one viewer exists
    /// at a time, so one extra instance covers it.
    let viewerAssetActions: AssetActionsCoordinator
    /// Runs Hide, Hide in Photos and Hide in ShotDex Only (FS-19.04 §3).
    var hideService: HideService {
        let photoLibrary = photoLibrary
        return HideService(database: database) { ids in
            try await photoLibrary.setHidden(true, for: PhotoLibraryService.fetchAssets(ids: ids))
        }
    }

    /// A coordinator of its own for one window's root. See `assetActions`.
    func makeAssetActions() -> AssetActionsCoordinator {
        let actions = AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity,
            originalDownloads: originalDownloads
        )
        actions.photoMarks = photoMarks
        actions.hideService = hideService
        actions.onHiddenInShotDex = { [sources] in sources.photosDeleted() }
        return actions
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
    /// Importing presets and looks, and later receiving them (FS-03.14).
    let lookExchange: LookExchangeModel
    /// The app-level banner every full-screen surface hosts (FS-03.14c §4).
    let banner: AppBannerModel
    /// Looks opened from AirDrop, Files, Messages or Mail (FS-03.14c §4).
    let lookInbox: LookInbox
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
    /// One server call at a time per connection for Backup, Upload and the
    /// server-source index (FS-19.07 §5).
    let connectionLock: ConnectionLock
    /// Which files are verified on a server (FS-15.02 §8).
    let serverUploads: ServerUploadStore
    /// Backup jobs and their ledger (FS-22).
    let backups: BackupStore
    /// AI Search providers the user added (FS-08.07).
    let aiProviders: AIProviderStore
    /// Keeps every backup job watching its source (FS-22.02).
    let backupCoordinator: BackupCoordinator
    /// Backup's background time (FS-22.02 §3).
    let backupBackground: BackupBackgroundService
    /// The set of uploaded asset ids the grid badge reads, kept in memory.
    let serverUploadIndex: ServerUploadIndex
    /// The photos whose RAW this iOS build can't read (FS-03.04b §3), kept
    /// in memory for the grid's glyph.
    let unsupportedRAWIndex: UnsupportedRAWIndex
    /// Pick/Reject flags and the star ratings not yet in Photos (FS-01.12).
    let photoMarksStore: PhotoMarksStore
    /// The same marks in memory, and the one place they are written.
    let photoMarks: PhotoMarks
    /// Bursts straight from PhotoKit, for the Bursts tab and the frame
    /// picker (FS-02.05, FS-06.06 §7b). Made on first use.
    @ObservationIgnored private(set) lazy var bursts: any BurstLibrary = PhotoKitBurstLibrary.makeForApp()
    /// iOS 27's first launch: pending stars into Photos, once (FS-01.12 §5).
    let ratingMigration: RatingMigrationPass
    /// Writes ShotDex's properties into Photos (iOS 27): stars, caption,
    /// keywords. Nil below iOS 27.
    let propertyWriter: (any PhotoPropertyWriting)?
    /// The mirror of Photos' caption and keywords (FS-02.07 §8).
    let photoKeywordStore: PhotoKeywordStore
    /// Reads Photos' caption and keywords; nil below iOS 27.
    let extendedMetadataReader: (any ExtendedMetadataReading)?
    /// The one writer of the mirror; nil below iOS 27.
    let keywordMirror: ExtendedMetadataMirrorPass?
    /// Caption and keyword writes from Info and the bulk sheet; nil below
    /// iOS 27, where the controls are hidden.
    let captionKeywords: CaptionKeywordService?
    /// The connections the selection ⋯ menu lists by name.
    let fileServerCatalog: FileServerCatalog
    /// Files brought down from a server (FS-17 §4).
    let serverDownloads: ServerDownloadStore
    /// What is kept on this device for offline use (intent keep-offline).
    let kept: KeptStore
    let keepRunner: KeepRunner
    let serverFileHistory: ServerFileHistory
    let serverShortcuts: ServerShortcutCatalog
    /// Server photo thumbnails and capture dates on disk (FS-17 §4).
    let serverThumbnails: RemoteThumbnailCache
    /// Folder and drive sources: adding them and reading them (FS-19.01).
    let folderSources: FolderSourceRunner
    /// Their folders, kept open once used.
    let folderRoots: FolderSourceRoots
    /// Stars, flags, keywords and recipes of file photos, out to their
    /// sidecars a second after the last change (FS-19.02 §5).
    let sidecarQueue: SidecarWriteQueue

    /// Move / Delete / Hide across sources (FS-19.04): Photos through
    /// PhotoKit's dialog, files to the Trash of their volume, NAS hidden.
    func makeDeletionService() -> DeletionService {
        let photoLibrary = photoLibrary
        let roots = folderRoots
        return DeletionService(
            database: database,
            deletePhotosAssets: { ids in try await photoLibrary.deleteAssetsCheckingServer(PhotoLibraryService.fetchAssets(ids: ids)) },
            root: { roots.root($0) }
        )
    }
    /// Connections added as sources: compared at launch, when the server
    /// comes back, and on Rescan (FS-19.03 §3).
    let serverSources: ServerSourceRefresh
    /// Whether Photos items are on the server sources (FS-19.07), checked
    /// while the app is in front.
    let onServerCheck: OnServerCheck
    /// Every Photos deletion that relies on a server copy asks it first
    /// (FS-19.07 §9).
    let photoDeletionGate: PhotoDeletionGate
    /// The check's own background slot (FS-19.07 §6, phase 2).
    let onServerBackground: OnServerBackgroundService
    /// Every source's row in Settings › Sources and the Sources group.
    let sources: SourcesModel
    /// Memory cards shown once, and which are plugged in (FS-20 §4).
    let cards = CardStore()
    /// The card import running, wherever the user is (FS-20 §7).
    let ingest = IngestCenter()
    /// iOS 26's continued processing for a card import (FS-20 AC-26).
    @ObservationIgnored lazy var ingestBackground = IngestBackgroundService(center: ingest)

    init(database: AppDatabase, photoLibrary: PhotoLibraryService, sharesIndex: Bool = false) {
        let metadataStore = MetadataStore(database: database)
        let indexTraffic = IndexTrafficMonitor()
        let indexInteractionGate = IndexInteractionGate()
        let indexShare = sharesIndex ? IndexShareService(store: SharedIndexStore(database: database)) : nil
        self.indexShare = indexShare
        let indexPipeline = IndexPipeline(
            metadataStore: MetadataStore(database: database),
            exifReader: ExifReader(trafficMonitor: indexTraffic),
            interactionGate: indexInteractionGate,
            sharedIndex: indexShare,
            readsOriginalsOnly: { IndexReadPolicy.readsOriginalsOnly }
        )
        self.database = database
        self.metadataStore = metadataStore
        // First observer of a finished index run: favorite and Photos rating
        // for every id Photos reported changed, read off the assets, no file
        // read (FS-01.12 AC-11).
        let factsRefresher = AssetFactsRefresher(metadataStore: metadataStore, readFacts: { @Sendable ids in AppDependencies.liveAssetFacts(ids) })
        indexPipeline.runObservers.add { changes in factsRefresher.refresh(changes) }
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
        Task {
            await photoRenderer.setMatteStore(.applicationSupport())
            // Nil until the Depth Anything model is in the bundle; Lens Blur
            // then leaves photos without a depth map as shot.
            await photoRenderer.setDepthEstimator(CoreMLDepthEstimator())
        }
        self.photoRenderer = photoRenderer
        let photoKitFetcher = PhotoKitOriginalFetcher()
        #if DEBUG
        let originalFetcher: any OriginalFetching = FakeOriginalFetcher.fromLaunchArguments(base: photoKitFetcher)
            ?? photoKitFetcher
        #else
        let originalFetcher: any OriginalFetching = photoKitFetcher
        #endif
        self.originalFetcher = originalFetcher
        self.photoEditing = PhotoEditingService(
            renderer: photoRenderer,
            indexNewAsset: { assetID in
                _ = await indexPipeline.indexSingle(assetId: assetID)
            },
            publishCreatedAsset: { _ in
                photoLibrary.publishAppCreatedAsset()
            }
        )
        photoEditing.originalFetcher = originalFetcher
        let photoRecipes = PhotoRecipeStore(database: database)
        photoEditing.savedFileRecipe = { photoId in (try? photoRecipes.recipe(photoId: photoId)) ?? nil }
        let placeStore = PlaceStore(database: database)
        let placeGeocoding = PlaceGeocodingService(store: placeStore)
        self.placeStore = placeStore
        self.placeGeocoding = placeGeocoding
        self.placeIndexPass = PlaceIndexPass(store: placeStore, geocoder: placeGeocoding)
        let recentSearches = RecentSearchStore()
        self.recentSearches = recentSearches
        let aiProviders = AIProviderStore(database: database, keys: KeychainPasswordStore(service: KeychainPasswordStore.aiProviderKeys))
        // One Apple Intelligence session for the app's life, made only on a
        // device that has it.
        let appleSearch: (any SearchModel)? = {
            if #available(iOS 26.0, *), AISearchTranslator.isAvailable() {
                return AppleIntelligenceSearchModel(translator: AISearchTranslator())
            }
            return nil
        }()
        self.searchService = SearchService(
            filterSuggestions: filterSuggestions,
            recentSearches: recentSearches,
            model: {
                let providers = (try? aiProviders.providers()) ?? []
                let choice = AIChoice.search(
                    stored: UserDefaults.standard.string(forKey: SettingsKeys.aiSearch),
                    providers: providers, onDevice: OnDeviceAI.choices
                )
                return SearchModelFactory.make(choice: choice, providers: providers, key: aiProviders.key(for:)) { appleSearch }
            }
        )
        self.compressionPresets = CompressionPresetStore()
        let overlayImages = OverlayImageStore()
        self.overlayImages = overlayImages
        self.signaturePresets = SignaturePresetStore(images: overlayImages)
        self.watermarkSettings = WatermarkSettingsStore()
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
        self.duplicateReview = DuplicateReviewSession(store: DuplicateReviewStore(database: database))
        self.duplicateQualityPass = DuplicateQualityPass(
            store: DuplicateQualityStore(database: database),
            reader: DuplicateQualityReader(),
            shouldPause: { indexInteractionGate.shouldPauseIndexing }
        )
        self.duplicateScanPipeline = DuplicateScanPipeline(
            store: perceptualHashStore,
            reader: PerceptualHashReader()
        )
        self.indexTraffic = indexTraffic
        self.indexInteractionGate = indexInteractionGate
        var availableBytes: @Sendable () -> Int64? = { DiskSpace.availableBytes() }
        #if DEBUG
        if let fake = originalFetcher as? FakeOriginalFetcher, let free = fake.freeBytes {
            availableBytes = { free }
        }
        #endif
        let originalDownloads = OriginalDownloadModel(
            fetcher: originalFetcher, gate: indexInteractionGate, availableBytes: availableBytes
        )
        self.originalDownloads = originalDownloads
        // Shares and drags stamp Watermark When Sharing (FS-05.04 §4).
        let shareWatermark = ShareWatermarkContext(
            settings: watermarkSettings, presets: signaturePresets, libraryQueries: libraryQueries,
            editing: photoEditing, imageExists: { [overlayImages] in overlayImages.imageExists(id: $0) }
        )
        originalDownloads.watermark = shareWatermark
        PhotoDragItem.watermarkContext = shareWatermark
        self.shareWatermark = shareWatermark
        let unsupportedRAWIndex = UnsupportedRAWIndex(store: RAWVerdictStore(database: database))
        self.unsupportedRAWIndex = unsupportedRAWIndex
        let photoMarksStore = PhotoMarksStore(database: database)
        self.photoMarksStore = photoMarksStore
        // Photos gone more than 30 days take their user data with them —
        // before anything loads marks (FS-19.05 §5).
        let orphans = PhotoOrphanStore(database: database)
        _ = try? orphans.purge(orphanedBefore: OrphanRetention.purgeCutoff(now: Date()))
        // iOS 27 keeps stars in Photos itself; below it they wait in
        // `pending_photo_rating` (FS-01.12 §4). Decided here, once.
        var ratingWriter: (any PhotoPropertyWriting)?
        if #available(iOS 27, *) { ratingWriter = PhotoKitPropertyWriter() }
        #if DEBUG
        if ratingWriter != nil, ProcessInfo.processInfo.arguments.contains(FailingPropertyWriter.launchArgument) {
            ratingWriter = FailingPropertyWriter()
        }
        if let base = ratingWriter, let refuse = RefusingPropertyWriter.count(in: ProcessInfo.processInfo.arguments) {
            ratingWriter = RefusingPropertyWriter(base: base, count: refuse)
        }
        #endif
        // Stars, flags and keywords of file photos go to the sidecars beside
        // their files (FS-19.02 §5), a second after the last change.
        let folderRoots = FolderSourceRoots(database: database)
        self.folderRoots = folderRoots
        let sidecarQueue = SidecarWriteQueue(writer: SidecarWriter(database: database) { sourceId, path in
            folderRoots.fileURL(sourceId: sourceId, relativePath: path)
        })
        self.sidecarQueue = sidecarQueue
        let photoMarks = PhotoMarks(
            store: photoMarksStore,
            metadataStore: metadataStore,
            ratingWriter: ratingWriter,
            readPhotosRatings: { @Sendable ids in
                PhotoLibraryService.fetchAssets(ids: ids).reduce(into: [:]) { result, asset in
                    if let rating = asset.photosStarRating { result[asset.localIdentifier] = rating }
                }
            },
            sidecarQueue: sidecarQueue
        )
        self.photoMarks = photoMarks
        self.propertyWriter = ratingWriter
        // Caption and keywords (FS-02.07): Photos holds them on iOS 27; the
        // mirror follows every index run's changed ids — Photos' "updated"
        // set, even when the modification date did not move (AC-10).
        let photoKeywordStore = PhotoKeywordStore(database: database)
        self.photoKeywordStore = photoKeywordStore
        var extendedMetadataReader: (any ExtendedMetadataReading)?
        if #available(iOS 27, *) { extendedMetadataReader = PhotoKitExtendedMetadataReader() }
        self.extendedMetadataReader = extendedMetadataReader
        if let extendedMetadataReader {
            let mirror = ExtendedMetadataMirrorPass(
                store: photoKeywordStore,
                reader: extendedMetadataReader,
                shouldPause: { indexInteractionGate.shouldPauseIndexing }
            )
            indexPipeline.runObservers.add { changes in await mirror.handle(changes) }
            self.keywordMirror = mirror
            if let ratingWriter {
                self.captionKeywords = CaptionKeywordService(
                    writer: ratingWriter,
                    reader: extendedMetadataReader,
                    mirror: mirror,
                    store: photoKeywordStore,
                    metadataStore: metadataStore,
                    keywordCatalog: { recount in
                        recount ? await filterSuggestions.refreshKeywords() : await filterSuggestions.load().keywords
                    }
                )
            } else {
                self.captionKeywords = nil
            }
        } else {
            self.keywordMirror = nil
            self.captionKeywords = nil
        }
        // A photo that leaves the library becomes an orphan: its stars and
        // flags leave memory at once and the database 30 days later
        // (FS-01.12 AC-9, `OrphanRetention`) — always when the app deleted it,
        // only with full access when an index run found it gone.
        photoLibrary.onAssetsDeleted = { ids in
            guard OrphanRetention.makesOrphans(on: .deletedInApp) else { return }
            await Task.detached(priority: .utility) { try? orphans.markGoneFromLibrary(ids: ids) }.value
            photoMarks.forget(ids)
        }
        indexPipeline.runObservers.add { changes in
            let ids = OrphanRetention.orphanIds(after: changes)
            guard !ids.isEmpty else { return }
            try? orphans.markGoneFromLibrary(ids: Array(ids))
            await photoMarks.forget(ids)
        }
        videoStudio.unreadableRAWIds = { unsupportedRAWIndex.assetIds }
        let recentActivity = RecentActivityStore()
        self.recentActivity = recentActivity
        let assetActions = AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity,
            originalDownloads: originalDownloads,
            unsupportedRAW: unsupportedRAWIndex
        )
        assetActions.photoMarks = photoMarks
        self.assetActions = assetActions
        let viewerAssetActions = AssetActionsCoordinator(
            photoLibrary: photoLibrary,
            metadataStore: metadataStore,
            recentActivity: recentActivity,
            originalDownloads: originalDownloads,
            unsupportedRAW: unsupportedRAWIndex
        )
        viewerAssetActions.photoMarks = photoMarks
        self.viewerAssetActions = viewerAssetActions
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
        self.lookExchange = LookExchangeModel(looks: lookPresets, luts: importedLUTs)
        let banner = AppBannerModel()
        self.banner = banner
        // A star Photos refused goes back on the tile and says so, with the
        // same command one tap away (FS-01.12 AC-10, NF-04).
        let readPhotosRatings: @Sendable ([String]) -> [String: Int] = { ids in
            PhotoLibraryService.fetchAssets(ids: ids).reduce(into: [:]) { result, asset in
                if let rating = asset.photosStarRating { result[asset.localIdentifier] = rating }
            }
        }
        let ratingMigration = RatingMigrationPass(
            store: photoMarksStore,
            metadataStore: metadataStore,
            writer: ratingWriter,
            readPhotosRatings: readPhotosRatings,
            accessIsFull: { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized }
        )
        ratingMigration.onMoved = { count in banner.show(MarkCopy.movedRatings(count)) }
        ratingMigration.onPendingChanged = { [weak photoMarks] in await photoMarks?.reload() }
        self.ratingMigration = ratingMigration
        photoMarks.onRatingWriteFailed = { [weak photoMarks] in
            banner.show(MarkCopy.ratingWriteFailed, actionTitle: MarkCopy.tryAgain) {
                Task { await photoMarks?.retryFailedRatingWrite() }
            }
        }
        self.lookInbox = LookInbox(looks: lookPresets, luts: importedLUTs, banner: banner)
        self.collectionsLayout = CollectionsLayoutStore()
        self.spotlight = SpotlightIndexer(
            libraryQueries: libraryQueries,
            smartAlbumStore: SmartAlbumStore(database: database)
        )
        self.photoWidgetSettings = PhotoWidgetSettingsStore(photoLibrary: photoLibrary)
        self.calendarWidgetWriter = CalendarSnapshotWriter()
        self.widgetLocation = WidgetLocationProvider()
        self.support = SupportService()
        let fileServers = FileServerStore(database: database, passwords: KeychainPasswordStore())
        self.fileServers = fileServers
        let connectionLock = ConnectionLock()
        self.connectionLock = connectionLock
        self.fileServerCatalog = FileServerCatalog(store: fileServers)
        let serverUploads = ServerUploadStore(database: database)
        self.serverUploads = serverUploads
        let backups = BackupStore(database: database)
        self.backups = backups
        self.aiProviders = aiProviders
        let backupCoordinator = BackupCoordinator(store: backups, environment: .live(
            database: database, store: backups, servers: fileServers, roots: folderRoots, connectionLock: connectionLock
        ))
        self.backupCoordinator = backupCoordinator
        self.backupBackground = BackupBackgroundService(coordinator: backupCoordinator, servers: fileServers)
        self.serverUploadIndex = ServerUploadIndex(store: serverUploads)
        self.serverDownloads = ServerDownloadStore(database: database)
        let kept = KeptStore(database: database)
        self.kept = kept
        let keptFiles = KeptFileStore.standard
        self.keepRunner = KeepRunner(store: kept, files: keptFiles, openCopies: OpenCopyQueries(database: database),
                                     folderRoots: folderRoots,
                                     serverLoader: ServerOriginalLoader(database: database, servers: fileServers))
        self.serverFileHistory = ServerFileHistory(database: database)
        self.serverShortcuts = ServerShortcutCatalog(store: ServerShortcutStore(database: database))
        PreviewCacheLocation.removeRetiredServerThumbnails()
        self.serverThumbnails = RemoteThumbnailCache.standard
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
        let sources = SourcesModel(database: database, runner: folderSources, servers: serverSources, photoLibrary: photoLibrary)
        self.sources = sources
        self.onServerCheck = OnServerCheck(environment: .live(
            database: database, servers: fileServers, refresh: serverSources, connectionLock: connectionLock,
            listingChanged: { await sources.serverListingChanged() }
        ))
        // The grid's "on server" glyph follows each batch of the check.
        let presence = OnServerProgressQueries(database: database)
        let uploadIndex = serverUploadIndex
        onServerCheck.onBatch = { uploadIndex.reloadPresence { try presence.presentAnywhere() } }
        uploadIndex.reloadPresence { try presence.presentAnywhere() }
        self.photoDeletionGate = PhotoDeletionGate(
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
        self.onServerBackground = OnServerBackgroundService(check: onServerCheck, needsPower: { [backups] in
            let connections = Set(((try? SourceStore(database: database).serverConnections()) ?? [:]).values)
            return ((try? backups.jobs()) ?? []).contains { connections.contains($0.connectionId) && $0.settings.onlyWhileCharging }
        })
        photoEditing.deletionGate = photoDeletionGate
        // Hide by where a photo lives (FS-19.04 §3), for every surface's menu.
        for actions in [assetActions, viewerAssetActions] {
            actions.hideService = hideService
            actions.onHiddenInShotDex = { [sources] in sources.photosDeleted() }
        }
        photoLibrary.fileThumbnails.reload(database)
        let openCopies = OpenCopyQueries(database: database)
        photoLibrary.filePhotoURL = { [folderRoots] id in
            guard let copy = try? openCopies.openCopy(photoId: id), copy.kind == "file", let path = copy.relativePath else { return nil }
            return folderRoots.fileURL(sourceId: copy.sourceId, relativePath: path)
        }
        // A kept file opens before anything is asked of PhotoKit or a server.
        photoLibrary.keptFileURL = { id in
            (try? kept.item(id: id)).flatMap { keptFiles.file(for: $0) }
        }
        sources.load()
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

    /// Favorite and Photos rating straight off the assets, for the ids that
    /// still exist.
    nonisolated static func liveAssetFacts(_ ids: [String]) -> [String: AssetFacts] {
        var facts: [String: AssetFacts] = [:]
        for asset in PhotoLibraryService.fetchAssets(ids: ids) {
            facts[asset.localIdentifier] = AssetFacts(isFavorite: asset.isFavorite, rating: asset.photosStarRating)
        }
        return facts
    }

    /// iOS 27's first launch: fills `photo_metadata.rating` for rows that
    /// have never read it, from the assets in memory — same shape and batch
    /// as `backfillMediaSubtypes`, so the star filter is right before the
    /// next index run reaches each photo. A no-op below iOS 27.
    func backfillRatings() async {
        guard #available(iOS 27, *) else { return }
        let store = metadataStore
        await Task.detached(priority: .utility) {
            while true {
                guard let ids = try? store.assetIdsMissingRating(limit: AssetFactsRefresher.batchSize),
                      !ids.isEmpty
                else { return }
                var facts = Self.liveAssetFacts(ids)
                // Ids PhotoKit no longer knows would be selected for ever;
                // 0 ends the loop and the next run deletes their rows.
                for id in ids where facts[id] == nil {
                    facts[id] = AssetFacts(isFavorite: false, rating: 0)
                }
                try? store.fillRatings(facts.mapValues { $0.rating ?? 0 })
                if ids.count < AssetFactsRefresher.batchSize { return }
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
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService(), sharesIndex: true)
    }

    static func preview() -> AppDependencies {
        let database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService())
    }
}

extension AppDependencies: LibraryServices {
    var indexRunAssertion: any IndexRunAssertion { backgroundIndex }
}
