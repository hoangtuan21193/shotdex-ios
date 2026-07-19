import Foundation
import Photos
import SwiftUI
import os

/// Presentation state for the Library tab: the whole filtered/sorted
/// library as slim grid rows, plus index pipeline coordination.
@MainActor
@Observable
final class LibraryController {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "index-net")

    private let queryDAO: LibraryQueryDAO
    private let metadataDAO: MetadataDAO
    private let pipeline: IndexPipeline
    private let backgroundIndex: BackgroundIndexService
    private let photoLibrary: PhotoLibraryService
    private let networkStatus: NetworkStatusService
    private let indexTraffic: IndexTrafficMonitor

    /// The whole filtered library as slim rows, in bottom-anchored display
    /// order: the sort's primary results sit at the END of the array = the
    /// bottom of the grid, like the system Photos app. Loaded in one query;
    /// the grid virtualizes rendering, so this is the only per-photo state.
    private(set) var items: [LibraryGridItem] = []
    /// Bumped whenever the content is replaced (filter/sort change, index
    /// run, retap). The screen re-ids its ScrollView off it so
    /// `defaultScrollAnchor(.bottom)` re-applies without a long-distance
    /// `scrollTo` (which would materialize thousands of lazy tiles).
    private(set) var contentGeneration = 0
    private(set) var isLoading = false
    private(set) var loadError: String?

    var matchCount: Int { items.count }

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Bounded PHAsset resolution for grid tiles: chunks of ids around the
    /// requested index, ≤5 chunks LRU (~2000 assets ceiling) — replaces the
    /// unbounded assets-by-id dictionary that grew with every page.
    @ObservationIgnored private lazy var assetCache = ChunkedLookupCache<PHAsset>(
        chunkSize: 400,
        maxChunks: 5,
        fetch: { ids in
            var byId: [String: PHAsset] = [:]
            for asset in PhotoLibraryService.fetchAssets(ids: ids) {
                byId[asset.localIdentifier] = asset
            }
            return byId
        }
    )
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

    private(set) var isIndexing = false
    private(set) var indexProgress: IndexProgress?
    /// Sampled once a second while indexing: connection type, bytes streamed
    /// from iCloud this run, and the download speed derived from the delta.
    private(set) var indexNetworkStatus: IndexNetworkStatus?

    var criteria: FilterCriteria = .empty {
        didSet { if criteria != oldValue { reload() } }
    }
    var sort: SortOption = .default {
        didSet { if sort != oldValue { reload() } }
    }

    /// Filter sheet option lists.
    private(set) var availableBrands: [String] = []
    private(set) var availableBodies: [String] = []
    private(set) var availableLenses: [String] = []

    init(dependencies: AppDependencies) {
        self.queryDAO = dependencies.libraryQueryDAO
        self.metadataDAO = dependencies.metadataDAO
        self.pipeline = dependencies.indexPipeline
        self.backgroundIndex = dependencies.backgroundIndex
        self.photoLibrary = dependencies.photoLibrary
        self.networkStatus = dependencies.networkStatus
        self.indexTraffic = dependencies.indexTraffic
        // Under memory pressure the PHAsset chunks are the one cache we
        // hold; visible tiles re-fetch their chunk on the next request.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.assetCache.removeAll()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    // MARK: Loading

    func reload() {
        loadTask?.cancel()
        loadError = nil
        isLoading = true
        let criteria = self.criteria
        let sort = self.sort
        let queryDAO = self.queryDAO
        // Fast path (no metadata filter + a date sort): drive the grid from
        // PhotoKit directly so the whole library shows instantly, like the
        // system Photos app, instead of waiting on the EXIF index. Any active
        // filter or metric sort falls back to the DB query.
        let usePhotoKit = criteria.isEmpty && sort.isDateSort
        loadTask = Task { [weak self] in
            do {
                let rows = usePhotoKit
                    ? try await Self.photoKitGridItems(sort: sort, queryDAO: queryDAO)
                    : try await queryDAO.gridItems(matching: criteria, sort: sort)
                guard let self, !Task.isCancelled else { return }
                // Reversed for the bottom-anchored grid; reversing in Swift
                // (not SQL) keeps NULLS LAST semantics = "No Date" at top.
                // `rows` is in sort order (newest-first for .dateTakenNewest)
                // from both paths, so the reverse is identical either way.
                self.items = Array(rows.reversed())
                self.assetCache.setIds(self.items.map(\.assetId))
                self.contentGeneration &+= 1
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.loadError = "Couldn't load photos."
                self.isLoading = false
            }
        }
    }

    /// The whole library as grid rows sourced from PhotoKit, in `sort` order.
    /// Each asset uses its indexed DB row when one exists (so the exposure
    /// overlay shows) and a PhotoKit-only placeholder otherwise — so photos
    /// appear before, and regardless of, the EXIF index. The PHFetchResult
    /// enumeration runs off the main thread (it materializes every asset).
    private static func photoKitGridItems(
        sort: SortOption,
        queryDAO: LibraryQueryDAO
    ) async throws -> [LibraryGridItem] {
        // Indexed rows keyed by id, for the exposure overlay. `.empty` +
        // matching sort reuses the existing query untouched.
        let indexed = try await queryDAO.gridItems(matching: .empty, sort: sort)
        var byId: [String: LibraryGridItem] = [:]
        byId.reserveCapacity(indexed.count)
        for row in indexed { byId[row.assetId] = row }

        let ascending = sort == .dateTakenOldest
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.predicate = PhotoLibraryService.browsableMediaPredicate
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: ascending)]
            let fetch = PHAsset.fetchAssets(with: options)
            var items: [LibraryGridItem] = []
            items.reserveCapacity(fetch.count)
            fetch.enumerateObjects { asset, _, _ in
                items.append(byId[asset.localIdentifier] ?? LibraryGridItem(asset: asset))
            }
            return items
        }.value
    }

    /// PHAsset for the tile at a flat grid index, via the bounded chunk
    /// cache. Nil while out of range (content just changed) or when the
    /// asset vanished from the photo library.
    func asset(atFlatIndex index: Int) -> PHAsset? {
        assetCache.value(at: index)
    }

    func refreshFilterOptions() {
        availableBrands = (try? queryDAO.distinctCameraBrands()) ?? []
        availableBodies = (try? queryDAO.distinctCameraBodies()) ?? []
        availableLenses = (try? queryDAO.distinctLenses()) ?? []
    }

    /// Autosuggest source for search: known camera + lens names.
    func suggestions(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let all = availableBodies + availableLenses + availableBrands
        return all.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(8).map { $0 }
    }

    // MARK: Indexing

    /// Streaming EXIF from iCloud is allowed on Wi-Fi; on cellular only when
    /// the user opted in via Settings. A closure — the pipeline re-evaluates
    /// it per batch, so the launch-triggered run isn't crippled by
    /// `NWPathMonitor`'s "expensive until first path update" default, and
    /// leaving Wi-Fi mid-run stops streaming at the next batch.
    private var allowNetworkForIndexing: @Sendable () -> Bool {
        let networkStatus = self.networkStatus
        return {
            !networkStatus.isExpensivePath
                || UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)
        }
    }

    func startIndexing(fullReindex: Bool = false) {
        guard !isIndexing else { return }
        let allowNetwork = allowNetworkForIndexing
        runPipeline(allowsNetwork: allowNetwork) { pipeline, onProgress in
            try await pipeline.run(fullReindex: fullReindex, allowNetwork: allowNetwork, onProgress: onProgress)
        }
    }

    /// Re-reads only the assets stuck at `pendingICloud`/`error`
    /// (Settings → Re-index Incomplete Photos). Always uses the network.
    func startReindexIncomplete() {
        guard !isIndexing else { return }
        runPipeline(allowsNetwork: { true }) { pipeline, onProgress in
            try await pipeline.reindexIncomplete(onProgress: onProgress)
        }
    }

    /// `allowsNetwork` mirrors what the pipeline run may do, so the status
    /// line can show speed/total (even at zero) whenever streaming is possible.
    private func runPipeline(
        allowsNetwork: @escaping @Sendable () -> Bool,
        _ operation: @escaping @Sendable (IndexPipeline, @escaping @Sendable (IndexProgress) -> Void) async throws -> IndexRunSummary
    ) {
        isIndexing = true
        indexProgress = nil
        indexTraffic.reset()
        Self.logger.log(
            "index run start: connection \(self.networkStatus.connectionType.displayName, privacy: .public), expensivePath \(self.networkStatus.isExpensivePath), allowCellularSetting \(UserDefaults.standard.bool(forKey: SettingsKeys.allowCellularIndexing)), allowNetwork \(allowsNetwork())"
        )
        indexNetworkStatus = IndexNetworkStatus(
            connection: networkStatus.connectionType,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            allowsNetwork: allowsNetwork()
        )
        let samplingTask = startNetworkSampling(allowsNetwork: allowsNetwork)
        // Keeps the run alive through a brief trip to the background;
        // on expiry it cancels cleanly and hands off to the BGProcessingTask.
        backgroundIndex.beginRunAssertion()
        let pipeline = self.pipeline
        Task {
            defer {
                samplingTask.cancel()
                self.isIndexing = false
                self.indexProgress = nil
                self.indexNetworkStatus = nil
                self.backgroundIndex.endRunAssertion()
            }
            do {
                _ = try await operation(pipeline) { progress in
                    Task { @MainActor in
                        self.indexProgress = progress
                    }
                }
            } catch {
                self.loadError = "Indexing failed."
            }
            self.reload()
            self.refreshFilterOptions()
        }
    }

    /// Once a second, snapshots the traffic counter and the network path;
    /// the byte delta between ticks is the displayed download speed.
    private func startNetworkSampling(allowsNetwork: @escaping @Sendable () -> Bool) -> Task<Void, Never> {
        let networkStatus = self.networkStatus
        let indexTraffic = self.indexTraffic
        return Task {
            var previousBytes: Int64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                let total = indexTraffic.totalBytes
                let speed = max(0, total - previousBytes)
                self.indexNetworkStatus = IndexNetworkStatus(
                    connection: networkStatus.connectionType,
                    bytesDownloaded: total,
                    bytesPerSecond: speed,
                    allowsNetwork: allowsNetwork()
                )
                Self.logger.debug(
                    "net sample: \(networkStatus.connectionType.displayName, privacy: .public), allowNetwork \(allowsNetwork()), downloaded \(total) B, speed \(speed) B/s"
                )
                previousBytes = total
            }
        }
    }

    func cancelIndexing() {
        let pipeline = self.pipeline
        Task { await pipeline.cancel() }
    }

    // MARK: Deletion

    /// Deletes the given assets via PhotoKit (system shows its own confirm
    /// dialog), then syncs the local index and in-memory state.
    /// Throws `PHPhotosError.userCancelled` if the user cancels.
    func deleteAssets(ids: Set<String>) async throws {
        let assets = PhotoLibraryService.fetchAssets(ids: Array(ids))
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        // PhotoKit is the source of truth; prune the DB rows right away so
        // the grid doesn't show stale entries until the next index run.
        try? metadataDAO.deleteAssets(ids: Array(ids))
        items.removeAll { ids.contains($0.assetId) }
        // Indexes shifted; rebuild the id list (drops cached chunks). No
        // contentGeneration bump — the user should keep their scroll spot.
        assetCache.setIds(items.map(\.assetId))
    }

    // MARK: Favorites

    /// DB only — slim grid rows carry no favorite flag (the grid never
    /// rendered it; favorites filtering is query-side).
    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataDAO.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }
}

// MARK: PhotoBrowsingSource

extension LibraryController: PhotoBrowsingSource {
    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        if let row = (try? queryDAO.metadata(assetId: assetId)) ?? nil {
            return row
        }
        // Not indexed yet (PhotoKit fast path): synthesize PhotoKit-only
        // metadata so the detail viewer still shows favorite/share/info
        // chrome and Compare keeps the photo instead of silently dropping it.
        return PhotoLibraryService.fetchAssets(ids: [assetId]).first
            .map { PhotoMetadata.placeholder(for: $0) }
    }

    func asset(for assetId: String) -> PHAsset? {
        PhotoLibraryService.fetchAssets(ids: [assetId]).first
    }

    /// Whole library is loaded as slim rows — nothing to page.
    func loadNextPageIfNeeded(currentIndex: Int) {}
}
