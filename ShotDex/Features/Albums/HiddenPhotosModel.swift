import Photos
import SwiftUI

/// Backs the Hidden section (FS-19.04 §3): every photo whose every copy
/// ShotDex has hidden — never the Photos app's Hidden album, which a
/// third-party app cannot read. Whole set loaded at once, like a smart album.
@MainActor
@Observable
final class HiddenPhotosModel {
    private let store: HiddenCopyStore
    private let libraryQueries: LibraryQueries
    private let metadataStore: MetadataStore
    private let pipeline: IndexPipeline
    private let photoLibrary: PhotoLibraryService

    /// Newest first.
    private(set) var items: [LibraryGridItem] = []
    /// The sources the hidden photos are on, for the grid's footer.
    private(set) var sourceNames: [String] = []
    private(set) var contentGeneration = 0
    private(set) var contentRefreshGeneration = 0
    private(set) var lastRemoval: PhotoGridRemoval?
    private(set) var isLoaded = false

    @ObservationIgnored private let assetCache: AsyncChunkedLookupCache<PHAsset>

    init(dependencies: AppDependencies) {
        self.store = HiddenCopyStore(database: dependencies.database)
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
        let rows = (try? await store.hiddenGridItems()) ?? []
        sourceNames = (try? store.hiddenSourceNames()) ?? []
        isLoaded = true
        guard rows.map(\.assetId) != items.map(\.assetId) else { return }
        items = rows
        assetCache.replaceKeys(items.map(\.assetId))
        contentGeneration &+= 1
    }

    func asset(atFlatIndex index: Int) -> PHAsset? {
        assetCache.value(at: index)
    }

    /// Unhide: every copy of each photo comes back to the library. A Photos
    /// copy hidden in Photos stays in Photos' Hidden album — only the Photos
    /// app can bring it back.
    func unhide(ids: [String]) throws {
        try store.unhide(photoIds: ids)
        drop(Set(ids))
        sourceNames = (try? store.hiddenSourceNames()) ?? []
    }

    private func drop(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lastRemoval = .next(after: lastRemoval, removing: ids)
        items.removeAll { ids.contains($0.assetId) }
        assetCache.replaceKeys(items.map(\.assetId))
        contentGeneration &+= 1
    }
}

// MARK: PhotoBrowsingSource

extension HiddenPhotosModel: PhotoBrowsingSource {
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
        try await photoLibrary.deleteAssetsCheckingServer(assets)
        try? metadataStore.deleteAssets(ids: [id])
        drop([id])
    }

    func removeDeleted(ids: Set<String>) {
        drop(ids)
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        await pipeline.indexSingle(assetId: assetId)
    }
}
