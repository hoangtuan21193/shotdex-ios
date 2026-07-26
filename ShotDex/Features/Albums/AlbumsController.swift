import Foundation
import Photos
import SwiftUI

/// One row in the Albums grid.
struct AlbumItem: Identifiable {
    enum Kind {
        case allPhotos
        case collection(PHAssetCollection)
    }

    var id: String
    var title: String
    var count: Int
    var kind: Kind
    var coverAsset: PHAsset?
    /// System-provided collection (Recents, Favorites, …) vs user album.
    var isSmart = false
    /// iCloud Shared Album (`PHAssetCollectionSubtype.albumCloudShared`).
    var isShared = false
}

/// One user-created smart album, resolved for display: the saved album plus
/// its live match count and cover from `LibraryQueryDAO`. PHAsset is not
/// Sendable but PhotoKit fetches are thread-safe, so this crosses the
/// off-main load boundary as `@unchecked Sendable` (mirrors `Snapshot`).
struct SmartAlbumTokenItem: Identifiable, @unchecked Sendable {
    let album: SmartAlbum
    let count: Int
    let coverAsset: PHAsset?

    var id: String { album.id }
}

/// Loads the album list: system smart albums, user albums, shared albums,
/// plus user-created smart albums (saved filters).
@MainActor
@Observable
final class AlbumsController {
    private(set) var albums: [AlbumItem] = []
    private(set) var isLoading = false

    /// Injected by the screen before the first `load()`; enables the
    /// smart-album (saved-filter) section, which needs the DB DAOs.
    var dependencies: AppDependencies?

    /// Summary for the "On This Day" hero card (today's date, previous years).
    private(set) var onThisDayCount = 0
    private(set) var onThisDayCover: PHAsset?

    /// User-created smart albums (saved filters), newest first.
    private(set) var smartQueryAlbums: [SmartAlbumTokenItem] = []

    var smartAlbums: [AlbumItem] { albums.filter(\.isSmart) }
    var userAlbums: [AlbumItem] { albums.filter { !$0.isSmart && !$0.isShared } }
    var sharedAlbums: [AlbumItem] { albums.filter { !$0.isSmart && $0.isShared } }

    /// Collections and counts fetched off the main thread; PHAsset fetches
    /// are thread-safe but expensive on large libraries.
    private struct Snapshot: @unchecked Sendable {
        var albums: [AlbumItem]
        var onThisDayCount: Int
        var onThisDayCover: PHAsset?
    }

    private struct CoverSnapshot: @unchecked Sendable {
        var asset: PHAsset?
    }

    /// Physical-pixel target for the full-width hero. Using the native display
    /// scale avoids the soft 1x rendition that is visible on 2x/3x screens.
    static var onThisDayCoverTargetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: 150 * scale
        )
    }

    /// Warms the On This Day hero independently of the lazily mounted Albums
    /// tab. Fetching the matching asset stays off-main; PhotoKit then prepares
    /// the exact display-sized rendition and PhotoLibraryService retains it.
    static func preheatOnThisDayCover(using photoLibrary: PhotoLibraryService) async {
        let snapshot = await Task.detached(priority: .utility) {
            CoverSnapshot(
                asset: OnThisDayController.fetchAssets(for: .now).firstObject
            )
        }.value
        guard let asset = snapshot.asset else { return }
        _ = photoLibrary.requestAlbumCover(
            for: asset,
            targetSize: onThisDayCoverTargetSize,
            allowNetwork: true
        ) { _ in }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        let deps = dependencies
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadSnapshot()
            }.value
            albums = snapshot.albums
            onThisDayCount = snapshot.onThisDayCount
            onThisDayCover = snapshot.onThisDayCover
            if let deps {
                smartQueryAlbums = await Self.loadSmartAlbums(
                    smartAlbumDAO: deps.smartAlbumDAO,
                    libraryQueryDAO: deps.libraryQueryDAO
                )
            }
            isLoading = false
        }
    }

    /// Deletes a user-created smart album and reloads.
    func deleteSmartAlbum(id: String) {
        try? dependencies?.smartAlbumDAO.delete(id: id)
        load()
    }

    /// Resolves each saved smart album's live count and cover off the main
    /// thread. `count` is a blocking reader read; `gridItems` runs on GRDB's
    /// reader pool.
    private nonisolated static func loadSmartAlbums(
        smartAlbumDAO: SmartAlbumDAO,
        libraryQueryDAO: LibraryQueryDAO
    ) async -> [SmartAlbumTokenItem] {
        guard let albums = try? smartAlbumDAO.fetchAllOrdered() else { return [] }
        var models: [SmartAlbumTokenItem] = []
        for album in albums {
            let count = (try? libraryQueryDAO.count(matching: album.query)) ?? 0
            var cover: PHAsset?
            if let firstId = try? await libraryQueryDAO
                .gridItems(matching: album.query, sort: .default, limit: 1)
                .first?.assetId {
                cover = PhotoLibraryService.fetchAssets(ids: [firstId]).first
            }
            models.append(SmartAlbumTokenItem(album: album, count: count, coverAsset: cover))
        }
        return models
    }

    private nonisolated static func loadSnapshot() -> Snapshot {
        var result: [AlbumItem] = []

        let imageOptions = PHFetchOptions()
        imageOptions.predicate = PhotoLibraryService.browsableMediaPredicate
        imageOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let onThisDay = OnThisDayController.fetchAssets(for: .now)

        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumRecentlyAdded,
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
        ]
        for subtype in smartSubtypes {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil
            )
            collections.enumerateObjects { collection, _, _ in
                if var item = Self.item(for: collection, imageOptions: imageOptions) {
                    item.isSmart = true
                    result.append(item)
                }
            }
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            if let item = Self.item(for: collection, imageOptions: imageOptions) {
                result.append(item)
            }
        }

        return Snapshot(
            albums: result,
            onThisDayCount: onThisDay.count,
            onThisDayCover: onThisDay.firstObject
        )
    }

    private nonisolated static func item(for collection: PHAssetCollection, imageOptions: PHFetchOptions) -> AlbumItem? {
        let assets = PHAsset.fetchAssets(in: collection, options: imageOptions)
        guard assets.count > 0 else { return nil }
        return AlbumItem(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Album",
            count: assets.count,
            kind: .collection(collection),
            coverAsset: assets.firstObject,
            isShared: collection.assetCollectionSubtype == .albumCloudShared
        )
    }
}

/// Pages one album's photos, joining PHAssets with their indexed metadata.
@MainActor
@Observable
final class AlbumDetailController: PhotoBrowsingSource {
    static let pageSize = 120

    private let metadataDAO: MetadataDAO
    private let database: AppDatabase
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline
    private let fetchResult: PHFetchResult<PHAsset>

    private(set) var photos: [PhotoMetadata] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var hasMorePages = true
    /// Ids of the tail of `photos`; O(1) membership test replaces the
    /// per-tile-appear `firstIndex` scan that lagged scrolling on big grids.
    private var pageTriggerIds: Set<String> = []

    /// Paging cursor into the immutable `fetchResult` snapshot. Tracked
    /// separately from `photos.count` because deletions prune `photos`
    /// without shifting the snapshot's indexes.
    private var nextFetchIndex = 0
    /// Deleted asset ids that may still sit in the `fetchResult` snapshot;
    /// skipped when later pages reach them.
    private var deletedIds: Set<String> = []

    init(album: AlbumItem, dependencies: AppDependencies) {
        self.metadataDAO = dependencies.metadataDAO
        self.database = dependencies.database
        self.photoLibrary = dependencies.photoLibrary
        self.indexPipeline = dependencies.indexPipeline

        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch album.kind {
        case .allPhotos:
            self.fetchResult = PHAsset.fetchAssets(with: options)
        case .collection(let collection):
            self.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        }
    }

    var totalCount: Int { fetchResult.count }

    func loadNextPage() {
        guard hasMorePages else { return }
        let start = nextFetchIndex
        let end = min(start + Self.pageSize, fetchResult.count)
        guard start < end else {
            hasMorePages = false
            return
        }

        var pageAssets: [PHAsset] = []
        pageAssets.reserveCapacity(end - start)
        for index in start..<end {
            let asset = fetchResult.object(at: index)
            guard !deletedIds.contains(asset.localIdentifier) else { continue }
            pageAssets.append(asset)
        }
        nextFetchIndex = end

        let ids = pageAssets.map(\.localIdentifier)
        let indexed = (try? fetchMetadata(ids: ids)) ?? [:]

        for asset in pageAssets {
            assetsById[asset.localIdentifier] = asset
            if let metadata = indexed[asset.localIdentifier] {
                photos.append(metadata)
            } else {
                // Asset not indexed yet — show it with PhotoKit facts only.
                photos.append(.placeholder(for: asset))
            }
        }
        hasMorePages = nextFetchIndex < fetchResult.count
        pageTriggerIds = Set(photos.suffix(30).map(\.assetId))
    }

    func loadNextPageIfNeeded(currentItem: PhotoMetadata) {
        guard pageTriggerIds.contains(currentItem.assetId) else { return }
        loadNextPage()
    }

    // MARK: PhotoBrowsingSource

    var photoCount: Int { photos.count }

    func photoId(at index: Int) -> String? {
        photos.indices.contains(index) ? photos[index].assetId : nil
    }

    func index(of assetId: String) -> Int? {
        photos.firstIndex { $0.assetId == assetId }
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        photos.first { $0.assetId == assetId }
    }

    func asset(for assetId: String) -> PHAsset? {
        assetsById[assetId]
    }

    /// Pager variant of the paging trigger: top up when the viewer nears
    /// the end of the loaded pages.
    func loadNextPageIfNeeded(currentIndex: Int) {
        guard currentIndex >= photos.count - 30 else { return }
        loadNextPage()
    }

    /// Deletes the given assets via PhotoKit (system shows its own confirm
    /// dialog), then syncs the local index and in-memory state.
    /// Throws `PHPhotosError.userCancelled` if the user cancels.
    func deleteAssets(ids: Set<String>) async throws {
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        // PhotoKit is the source of truth; prune the DB rows right away so
        // the grid doesn't show stale entries until the next index run.
        try? metadataDAO.deleteAssets(ids: Array(ids))
        deletedIds.formUnion(ids)
        photos.removeAll { ids.contains($0.assetId) }
        pageTriggerIds = Set(photos.suffix(30).map(\.assetId))
        for id in ids {
            assetsById.removeValue(forKey: id)
        }
    }

    func deleteAsset(id: String) async throws {
        try await deleteAssets(ids: [id])
    }

    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataDAO.updateFavorite(assetId: assetId, isFavorite: isFavorite)
        if let index = photos.firstIndex(where: { $0.assetId == assetId }) {
            photos[index].isFavorite = isFavorite
        }
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        guard let updated = await indexPipeline.indexSingle(assetId: assetId) else { return nil }
        // Keep the in-memory page (this source serves metadata from `photos`).
        if let index = photos.firstIndex(where: { $0.assetId == assetId }) {
            photos[index] = updated
        }
        return updated
    }

    private func fetchMetadata(ids: [String]) throws -> [String: PhotoMetadata] {
        guard !ids.isEmpty else { return [:] }
        let rows = try database.reader.read { db in
            try PhotoMetadata.fetchAll(db, keys: ids)
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.assetId, $0) })
    }
}
