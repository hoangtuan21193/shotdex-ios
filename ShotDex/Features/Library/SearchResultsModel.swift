import Foundation
import Photos

/// The photos a search finds, as the grid and the viewer read them
/// (FS-01.03c §4): the rows come from `SearchSession`; PhotoKit assets and
/// full metadata are fetched as cells and pages ask, not up front — a search
/// can match the whole library.
@MainActor
@Observable
final class SearchResultsModel: PhotoBrowsingSource {
    private(set) var items: [LibraryGridItem] = []
    /// Bumped when the rows are replaced, so the grid reloads.
    private(set) var contentGeneration = 0
    private(set) var lastRemoval: PhotoGridRemoval?

    private let libraryQueries: LibraryQueries
    private let metadataStore: MetadataStore
    private let photoLibrary: PhotoLibraryService
    @ObservationIgnored private var assetsById: [String: PHAsset] = [:]
    @ObservationIgnored private var metadataById: [String: PhotoMetadata] = [:]
    @ObservationIgnored private var indexById: [String: Int] = [:]
    @ObservationIgnored private var prefetch: Task<Void, Never>?

    /// Assets fetched ahead of the grid, in one PhotoKit call off the main actor.
    static let prefetchCount = 120

    init(dependencies: AppDependencies) {
        self.libraryQueries = dependencies.libraryQueries
        self.metadataStore = dependencies.metadataStore
        self.photoLibrary = dependencies.photoLibrary
    }

    func update(_ rows: [LibraryGridItem]) {
        guard rows.map(\.assetId) != items.map(\.assetId) else { return }
        items = rows
        indexById = Dictionary(rows.enumerated().map { ($1.assetId, $0) }, uniquingKeysWith: { first, _ in first })
        contentGeneration &+= 1
        let ids = rows.prefix(Self.prefetchCount).map(\.assetId).filter { assetsById[$0] == nil }
        prefetch?.cancel()
        guard !ids.isEmpty else { return }
        prefetch = Task { [weak self] in
            let fetched = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.fetchAssets(ids: ids)
            }.value
            guard !Task.isCancelled, let self else { return }
            for asset in fetched { self.assetsById[asset.localIdentifier] = asset }
        }
    }

    // MARK: PhotoBrowsingSource

    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func index(of assetId: String) -> Int? { indexById[assetId] }

    func asset(for assetId: String) -> PHAsset? {
        if let asset = assetsById[assetId] { return asset }
        let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first
        if let asset { assetsById[assetId] = asset }
        return asset
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        if let row = metadataById[assetId] { return row }
        let row = (try? libraryQueries.metadata(assetIds: [assetId]))?[assetId]
        if let row { metadataById[assetId] = row }
        return row
    }

    func loadNextPageIfNeeded(currentIndex: Int) {}

    func syncFavorite(assetId: String, isFavorite: Bool) {
        metadataById[assetId]?.isFavorite = isFavorite
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }

    func deleteAsset(id: String) async throws {
        guard let asset = asset(for: id) else { return }
        try await photoLibrary.deleteAssetsCheckingServer([asset])
        try? metadataStore.deleteAssets(ids: [id])
        removeDeleted(ids: [id])
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? { nil }

    func removeDeleted(ids: Set<String>) {
        lastRemoval = .next(after: lastRemoval, removing: ids)
        items.removeAll { ids.contains($0.assetId) }
        for id in ids {
            assetsById.removeValue(forKey: id)
            metadataById.removeValue(forKey: id)
        }
        indexById = Dictionary(items.enumerated().map { ($1.assetId, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
