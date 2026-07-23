import Photos
import SwiftUI

/// Backs the smart-album detail grid. The album's photos are the result of
/// replaying its saved `FilterCriteria` through `LibraryQueryDAO` — so this
/// mirrors `LibraryController` (query-driven, whole set loaded once) rather
/// than `AlbumDetailController` (paged over a `PHFetchResult`). Trimmed: no
/// index pipeline UI, no PhotoKit fast path, no auto-retry.
@MainActor
@Observable
final class SmartAlbumDetailController {
    private let queryDAO: LibraryQueryDAO
    private let metadataDAO: MetadataDAO
    private let photoLibrary: PhotoLibraryService
    private let pipeline: IndexPipeline
    private let query: SmartAlbumQuery

    /// Matching rows in display sort order (newest first = top of the grid;
    /// top-anchored, so no reverse — unlike the bottom-anchored Library grid).
    private(set) var items: [LibraryGridItem] = []
    /// Bumped when the content is replaced (initial load, delete) so the grid
    /// re-anchors.
    private(set) var contentGeneration = 0
    private(set) var isLoading = false

    var matchCount: Int { items.count }

    /// Bounded PHAsset resolution for grid tiles (same policy as Library).
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

    init(album: SmartAlbum, dependencies: AppDependencies) {
        self.queryDAO = dependencies.libraryQueryDAO
        self.metadataDAO = dependencies.metadataDAO
        self.photoLibrary = dependencies.photoLibrary
        self.pipeline = dependencies.indexPipeline
        self.query = album.query
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let rows = (try? await queryDAO.gridItems(matching: query, sort: .default)) ?? []
        items = rows
        assetCache.setIds(items.map(\.assetId))
        contentGeneration &+= 1
    }

    /// PHAsset for the tile at a flat grid index, via the bounded chunk cache.
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
        try? metadataDAO.deleteAssets(ids: Array(ids))
        items.removeAll { ids.contains($0.assetId) }
        assetCache.setIds(items.map(\.assetId))
        contentGeneration &+= 1
    }
}

// MARK: PhotoBrowsingSource

extension SmartAlbumDetailController: PhotoBrowsingSource {
    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func index(of assetId: String) -> Int? {
        items.firstIndex { $0.assetId == assetId }
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        if let row = (try? queryDAO.metadata(assetId: assetId)) ?? nil {
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
        try? metadataDAO.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }

    func deleteAsset(id: String) async throws {
        try await deleteAssets(ids: [id])
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        await pipeline.indexSingle(assetId: assetId)
    }
}
