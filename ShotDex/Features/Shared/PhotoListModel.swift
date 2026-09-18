import Foundation
import Photos
import SwiftUI

/// A browsable run of photos defined by nothing but a list of asset ids.
///
/// Album Detail is backed by a `PHAssetCollection` and Smart Album Detail by a
/// saved query; neither shape fits a set the app computed itself — the photos
/// around one place, the photos of one trip, the photos chosen for a memory.
/// This is that third shape, and it feeds the shared grid and the fullscreen
/// viewer like the other two.
@MainActor
@Observable
final class PhotoListModel: PhotoBrowsingSource {
    private(set) var items: [LibraryGridItem] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var isLoading = false
    /// Bumped when the list is replaced, so the grid reloads and re-anchors.
    private(set) var contentGeneration = 0
    private(set) var lastRemoval: PhotoGridRemoval?

    private let assetIds: [String]
    private let libraryQueries: LibraryQueries
    private let metadataStore: MetadataStore
    private let photoLibrary: PhotoLibraryService
    private var metadataById: [String: PhotoMetadata] = [:]
    private var indexById: [String: Int] = [:]

    init(assetIds: [String], dependencies: AppDependencies) {
        self.assetIds = assetIds
        self.libraryQueries = dependencies.libraryQueries
        self.metadataStore = dependencies.metadataStore
        self.photoLibrary = dependencies.photoLibrary
    }

    func load() {
        guard !isLoading, items.isEmpty else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            let ids = assetIds
            let rows = (try? libraryQueries.metadata(assetIds: ids)) ?? [:]
            let assets = PhotoLibraryService.fetchAssets(ids: ids)
            var byId: [String: PHAsset] = [:]
            for asset in assets { byId[asset.localIdentifier] = asset }

            // Keep the caller's order: it is meaningful (a trip runs forward in
            // time, a memory is curated), and re-sorting would throw that away.
            // Ids PhotoKit no longer knows are dropped.
            var resolved: [LibraryGridItem] = []
            resolved.reserveCapacity(ids.count)
            for id in ids {
                guard let asset = byId[id] else { continue }
                if let row = rows[id] {
                    resolved.append(LibraryGridItem(metadata: row))
                } else {
                    resolved.append(LibraryGridItem(asset: asset))
                }
            }
            metadataById = rows
            assetsById = byId
            items = resolved
            indexById = Dictionary(
                uniqueKeysWithValues: resolved.enumerated().map { ($1.assetId, $0) }
            )
            contentGeneration &+= 1
        }
    }

    // MARK: PhotoBrowsingSource

    var photoCount: Int { items.count }

    func photoId(at index: Int) -> String? {
        items.indices.contains(index) ? items[index].assetId : nil
    }

    func index(of assetId: String) -> Int? { indexById[assetId] }

    func metadata(for assetId: String) -> PhotoMetadata? { metadataById[assetId] }

    func asset(for assetId: String) -> PHAsset? { assetsById[assetId] }

    func loadNextPageIfNeeded(currentIndex: Int) {}

    func syncFavorite(assetId: String, isFavorite: Bool) {
        metadataById[assetId]?.isFavorite = isFavorite
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
    }

    func deleteAsset(id: String) async throws {
        guard let asset = assetsById[id] else { return }
        try await photoLibrary.deleteAssets([asset])
        try? metadataStore.deleteAssets(ids: [id])
        remove(ids: [id])
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? { nil }

    // MARK: Mutation

    func deleteAssets(ids: Set<String>) async throws {
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        try? metadataStore.deleteAssets(ids: Array(ids))
        remove(ids: ids)
    }

    private func remove(ids: Set<String>) {
        lastRemoval = .next(after: lastRemoval, removing: ids)
        items.removeAll { ids.contains($0.assetId) }
        for id in ids {
            assetsById.removeValue(forKey: id)
            metadataById.removeValue(forKey: id)
        }
        indexById = Dictionary(
            uniqueKeysWithValues: items.enumerated().map { ($1.assetId, $0) }
        )
    }
}
