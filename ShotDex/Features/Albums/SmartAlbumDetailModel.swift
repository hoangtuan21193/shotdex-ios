import Photos
import SwiftUI

/// Backs the smart-album detail grid. The album's photos are the result of
/// replaying its saved `FilterCriteria` through `LibraryQueries` — so this
/// mirrors `LibraryModel` (query-driven, whole set loaded once) rather
/// than `AlbumDetailModel` (paged over a `PHFetchResult`). Trimmed: no
/// index pipeline UI, no PhotoKit fast path, no auto-retry.
@MainActor
@Observable
final class SmartAlbumDetailModel {
    private let libraryQueries: LibraryQueries
    private let metadataStore: MetadataStore
    private let photoLibrary: PhotoLibraryService
    private let pipeline: IndexPipeline
    private let query: SmartAlbumQuery
    private let albumId: String

    /// Newest or oldest first, remembered per album (FS-06.01b §3). A smart
    /// album is a query, so there is no album order to offer.
    private(set) var sortOrder: AlbumSortOrder
    /// The Filter menu's narrowing (FS-06.09): ANDed onto the saved query,
    /// never written into it.
    private(set) var filter = AlbumFilter()
    /// Matches of the saved query alone — the "of 20" while filtering.
    private(set) var unfilteredCount = 0

    /// Matching rows in display sort order (newest first = top of the grid;
    /// top-anchored, so no reverse — unlike the bottom-anchored Library grid).
    private(set) var items: [LibraryGridItem] = []
    /// Bumped when the content is replaced (initial load, delete) so the grid
    /// re-anchors.
    private(set) var contentGeneration = 0
    /// Bumped when an async PHAsset chunk becomes available; visible cells
    /// reconfigure in place without rebuilding/re-anchoring the grid.
    private(set) var contentRefreshGeneration = 0
    /// Latest in-place deletion, published in the same update as the pruned
    /// list so the grid animates the tiles out instead of reloading.
    private(set) var lastRemoval: PhotoGridRemoval?
    private(set) var isLoading = false

    var matchCount: Int { items.count }

    /// Bounded, non-blocking PHAsset resolution for grid tiles (same policy as
    /// Library). Cache misses paint placeholders while the chunk resolves.
    @ObservationIgnored private let assetCache: AsyncChunkedLookupCache<PHAsset>

    init(album: SmartAlbum, dependencies: AppDependencies) {
        self.libraryQueries = dependencies.libraryQueries
        self.metadataStore = dependencies.metadataStore
        self.photoLibrary = dependencies.photoLibrary
        self.pipeline = dependencies.indexPipeline
        self.query = album.query
        self.albumId = album.id
        self.sortOrder = AlbumSortStore.order(for: album.id, isSmartAlbum: true)
        let assetCache = AsyncChunkedLookupCache<PHAsset>(
            chunkSize: 120,
            maxChunks: 6,
            fetch: { ids in
                var byId: [String: PHAsset] = [:]
                for asset in PhotoLibraryService.fetchAssets(ids: ids) {
                    byId[asset.localIdentifier] = asset
                }
                return byId
            }
        )
        self.assetCache = assetCache
        assetCache.onChunkLoaded = { [weak self] in
            self?.contentRefreshGeneration &+= 1
        }
    }

    func setSortOrder(_ order: AlbumSortOrder) async {
        guard order != sortOrder, order != .albumOrder else { return }
        sortOrder = order
        AlbumSortStore.setOrder(order, for: albumId)
        await load()
    }

    func setFilter(_ newValue: AlbumFilter) async {
        guard newValue != filter else { return }
        filter = newValue
        await load()
    }

    /// How many of the album's photos a query would leave — the Advanced
    /// sheet's live count, on top of the saved query.
    func countMatching(_ advanced: SmartAlbumQuery) async -> Int {
        (try? await libraryQueries.count(matchingAll: [.query(query), .query(advanced)])) ?? 0
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        var filters: [LibraryQueries.IndexFilter] = [.query(query)]
        if let advanced = filter.advancedQuery {
            filters.append(.query(advanced))
        } else if !filter.criteria.isEmpty {
            filters.append(.criteria(filter.criteria))
        }
        let requested = (filter, sortOrder)
        let rows = (try? await libraryQueries.gridItems(
            matchingAll: filters,
            sort: sortOrder.librarySort
        )) ?? []
        let total = filter.isActive
            ? ((try? await libraryQueries.count(matchingAll: [.query(query)])) ?? 0)
            : rows.count
        // A newer filter or order has started its own load.
        guard requested == (filter, sortOrder) else { return }
        unfilteredCount = total
        // The library-change reload after our own delete returns the list we
        // already pruned: refresh tiles in place, keep the scroll position.
        let sameList = rows.count == items.count
            && zip(rows, items).allSatisfy { $0.assetId == $1.assetId }
        items = rows
        if sameList {
            contentRefreshGeneration &+= 1
        } else {
            assetCache.replaceKeys(items.map(\.assetId))
            contentGeneration &+= 1
        }
    }

    /// Returns immediately; a miss starts an off-main chunk lookup.
    func asset(atFlatIndex index: Int) -> PHAsset? {
        assetCache.value(at: index)
    }

    // MARK: Deletion

    /// Deletes via PhotoKit (system confirm dialog), prunes the DB, and drops
    /// the rows locally. Throws `PHPhotosError.userCancelled` on cancel.
    func deleteAssets(ids: Set<String>) async throws {
        let assets = PhotoLibraryService.fetchAssets(ids: Array(ids))
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        try? metadataStore.deleteAssets(ids: Array(ids))
        lastRemoval = .next(after: lastRemoval, removing: ids)
        items.removeAll { ids.contains($0.assetId) }
        assetCache.replaceKeys(items.map(\.assetId))
        // The grid consumes this bump together with `lastRemoval`; it is the
        // fallback reload if the removal cannot be applied in place.
        contentGeneration &+= 1
    }
}

// MARK: PhotoBrowsingSource

extension SmartAlbumDetailModel: PhotoBrowsingSource {
    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func index(of assetId: String) -> Int? {
        items.firstIndex { $0.assetId == assetId }
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        if let row = (try? libraryQueries.metadata(assetId: assetId)) ?? nil {
            return row
        }
        return PhotoLibraryService.fetchAssets(ids: [assetId]).first
            .map { PhotoMetadata.placeholder(for: $0) }
    }

    func asset(for assetId: String) -> PHAsset? {
        PhotoLibraryService.fetchAssets(ids: [assetId]).first
    }

    /// Whole matching set is loaded at once — nothing to page.
    func loadNextPageIfNeeded(currentIndex: Int) {}

    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }

    func deleteAsset(id: String) async throws {
        try await deleteAssets(ids: [id])
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        await pipeline.indexSingle(assetId: assetId)
    }
}
