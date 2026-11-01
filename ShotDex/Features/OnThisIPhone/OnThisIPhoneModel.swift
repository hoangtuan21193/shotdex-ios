import Photos
import SwiftUI

/// Backs Utilities › On This iPhone: every kept photo and video that is on
/// the device, newest first, plus the albums kept as a whole and what is
/// still waiting. Built like the Hidden section's model.
@MainActor
@Observable
final class OnThisIPhoneModel {
    private let store: KeptStore
    private let libraryQueries: LibraryQueries
    private let metadataStore: MetadataStore
    private let pipeline: IndexPipeline
    private let photoLibrary: PhotoLibraryService

    /// The kept items that are here, newest first.
    private(set) var items: [LibraryGridItem] = []
    private(set) var albums: [KeptAlbum] = []
    private(set) var albumProgress: [String: (onDevice: Int, total: Int)] = [:]
    private(set) var failed: [KeptItem] = []
    private(set) var waitingCount = 0
    private(set) var keptBytes: Int64 = 0
    private(set) var keptPhotoCount = 0
    private(set) var keptVideoCount = 0
    private(set) var contentGeneration = 0
    private(set) var contentRefreshGeneration = 0
    private(set) var lastRemoval: PhotoGridRemoval?
    private(set) var isLoaded = false

    @ObservationIgnored private let assetCache: AsyncChunkedLookupCache<PHAsset>

    init(dependencies: AppDependencies) {
        self.store = dependencies.kept
        self.libraryQueries = dependencies.libraryQueries
        self.metadataStore = dependencies.metadataStore
        self.pipeline = dependencies.indexPipeline
        self.photoLibrary = dependencies.photoLibrary
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

    func load() async {
        let kept = (try? store.items()) ?? []
        let here = kept.filter { $0.state == .onDevice }
        failed = kept.filter { $0.state == .failed || $0.state == .missing }
        waitingCount = kept.filter { $0.state == .queued || $0.state == .downloading }.count
        keptBytes = here.reduce(0) { $0 + $1.byteCount }
        keptVideoCount = here.filter(\.isVideo).count
        keptPhotoCount = here.count - keptVideoCount
        albums = (try? store.albums()) ?? []
        albumProgress = (try? store.albumProgress()) ?? [:]
        let rows = (try? await libraryQueries.gridItems(matchingAll: [], restrictedTo: here.map(\.id), sort: .dateTakenNewest)) ?? []
        isLoaded = true
        guard rows.map(\.assetId) != items.map(\.assetId) else { return }
        items = rows
        assetCache.replaceKeys(items.map(\.assetId))
        contentGeneration &+= 1
    }

    func asset(atFlatIndex index: Int) -> PHAsset? {
        assetCache.value(at: index)
    }

    /// Drops removed ids from the grid at once; the runner has deleted the
    /// files and rows.
    func dropped(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lastRemoval = .next(after: lastRemoval, removing: ids)
        items.removeAll { ids.contains($0.assetId) }
        assetCache.replaceKeys(items.map(\.assetId))
        contentGeneration &+= 1
    }
}

// MARK: PhotoBrowsingSource

extension OnThisIPhoneModel: PhotoBrowsingSource {
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

    func loadNextPageIfNeeded(currentIndex: Int) {}

    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }

    func deleteAsset(id: String) async throws {
        let assets = PhotoLibraryService.fetchAssets(ids: [id])
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        try? metadataStore.deleteAssets(ids: [id])
        dropped([id])
    }

    func removeDeleted(ids: Set<String>) {
        dropped(ids)
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        await pipeline.indexSingle(assetId: assetId)
    }
}
