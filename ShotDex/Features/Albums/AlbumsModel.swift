import Foundation
import Photos
import SwiftUI

/// Which section of the Collections screen an album belongs to. Mirrors the
/// grouping iOS Photos uses, so a user who knows Photos finds the same album
/// in the same band.
enum AlbumGroup {
    /// Recents and Favorites — the two system albums people reach for most.
    case suggested
    /// Capture-format collections: Videos, Selfies, Live Photos, Portrait,
    /// Panoramas, Bursts, RAW and the rest.
    case mediaType
    /// Library housekeeping rather than browsing: Hidden, Unable to Upload.
    case utility
    /// An album the user made.
    case user
    /// An iCloud Shared Album.
    case shared
}

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
    var group: AlbumGroup = .user
    /// SF Symbol shown instead of a cover when the album has no thumbnail
    /// worth showing — media-type and utility albums carry one.
    var symbolName: String?
    /// System-provided collection (Recents, Favorites, …) vs user album.
    var isSmart = false
    /// iCloud Shared Album (`PHAssetCollectionSubtype.albumCloudShared`).
    var isShared = false
}

/// One user-created smart album, resolved for display: the saved album plus
/// its live match count and cover from `LibraryQueries`. PHAsset is not
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
final class AlbumsModel {
    private(set) var albums: [AlbumItem] = []
    private(set) var isLoading = false

    /// Enables the smart-album (saved-filter) section, which needs the DB
    /// queries. Injected at init by the root (which preloads the snapshot);
    /// still settable for the previews/tests that build the model bare.
    var dependencies: AppDependencies?

    /// `assetChangeToken` the current snapshot was built from. The screen asks
    /// for a load on every appearance and on every structural library change;
    /// rebuilding an unchanged snapshot costs a `PHAsset.fetchAssets(in:)` plus
    /// `count` per collection — 300–670ms here — so it is skipped.
    private var loadedAssetToken: Int?

    init(dependencies: AppDependencies? = nil) {
        self.dependencies = dependencies
    }

    /// Summary for the "On This Day" hero card (today's date, previous years).
    private(set) var onThisDayCount = 0
    private(set) var onThisDayCover: PHAsset?

    /// User-created smart albums (saved filters), newest first.
    private(set) var smartQueryAlbums: [SmartAlbumTokenItem] = []

    var smartAlbums: [AlbumItem] { albums.filter { $0.group == .suggested } }
    var mediaTypeAlbums: [AlbumItem] { albums.filter { $0.group == .mediaType } }
    var utilityAlbums: [AlbumItem] { albums.filter { $0.group == .utility } }
    var userAlbums: [AlbumItem] { albums.filter { $0.group == .user } }
    var sharedAlbums: [AlbumItem] { albums.filter { $0.group == .shared } }

    /// Collections and counts fetched off the main thread; PHAsset fetches
    /// are thread-safe but expensive on large libraries.
    private struct Snapshot: @unchecked Sendable {
        var albums: [AlbumItem]
        var folders: [FolderItem]
        var onThisDayCount: Int
        var onThisDayCover: PHAsset?
    }

    private struct CoverSnapshot: @unchecked Sendable {
        var asset: PHAsset?
    }

    /// Physical-pixel target for the full-width hero. Using the native display
    /// scale avoids the soft 1x rendition that is visible on 2x/3x screens.
    static var onThisDayCoverTargetSize: CGSize {
        let scale = ActiveDisplay.scale
        return CGSize(
            width: ActiveDisplay.size.width * scale,
            height: 150 * scale
        )
    }

    /// Warms the On This Day hero independently of the lazily mounted Albums
    /// tab. Fetching the matching asset stays off-main; PhotoKit then prepares
    /// the exact display-sized rendition and PhotoLibraryService retains it.
    static func preheatOnThisDayCover(using photoLibrary: PhotoLibraryService) async {
        let snapshot = await Task.detached(priority: .utility) {
            CoverSnapshot(
                asset: OnThisDayModel.fetchAssets(for: .now).firstObject
            )
        }.value
        guard let asset = snapshot.asset else { return }
        _ = photoLibrary.requestAlbumCover(
            for: asset,
            targetSize: onThisDayCoverTargetSize,
            allowNetwork: true
        ) { _ in }
    }

    /// Builds the snapshot unless one already exists for this structural state.
    /// `nil` token means "rebuild regardless" (a smart album was edited).
    func load(forAssetToken token: Int?) {
        if let token, token == loadedAssetToken, !albums.isEmpty { return }
        loadedAssetToken = token
        load()
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
            folders = snapshot.folders
            onThisDayCount = snapshot.onThisDayCount
            onThisDayCover = snapshot.onThisDayCover
            if let deps {
                smartQueryAlbums = await Self.loadSmartAlbums(
                    smartAlbumStore: deps.smartAlbumStore,
                    libraryQueries: deps.libraryQueries
                )
                await loadMemories(libraryQueries: deps.libraryQueries)
            }
            isLoading = false
        }
    }

    /// User folders and the albums inside each, for the Folders section.
    private(set) var folders: [FolderItem] = []
    /// Auto-curated collections for the Memories row.
    private(set) var memories: [Memory] = []

    /// One user folder plus the albums directly inside it.
    struct FolderItem: Identifiable {
        let collectionList: PHCollectionList
        let albums: [AlbumItem]

        var id: String { collectionList.localIdentifier }
        var title: String { collectionList.localizedTitle ?? "Folder" }
    }

    // MARK: Album lifecycle

    func createAlbum(named name: String) {
        Task {
            _ = try? await photoLibraryService?.createAlbum(named: name)
            load()
        }
    }

    func createFolder(named name: String) {
        Task {
            _ = try? await photoLibraryService?.createFolder(named: name)
            load()
        }
    }

    func rename(_ album: AlbumItem, to name: String) {
        guard case .collection(let collection) = album.kind else { return }
        Task {
            try? await photoLibraryService?.renameAlbum(collection, to: name)
            load()
        }
    }

    func delete(_ album: AlbumItem) {
        guard case .collection(let collection) = album.kind else { return }
        Task {
            try? await photoLibraryService?.deleteAlbums([collection])
            load()
        }
    }

    func rename(_ folder: FolderItem, to name: String) {
        Task {
            try? await photoLibraryService?.renameFolder(folder.collectionList, to: name)
            load()
        }
    }

    func delete(_ folder: FolderItem) {
        Task {
            try? await photoLibraryService?.deleteFolders([folder.collectionList])
            load()
        }
    }

    /// Moves a user album into a folder, or back to the top level when
    /// `folder` is nil.
    func move(_ album: AlbumItem, to folder: FolderItem?) {
        guard case .collection(let collection) = album.kind else { return }
        Task {
            // Out of whichever folder currently holds it, before it can go
            // into another: PhotoKit lets a collection sit in only one.
            for existing in folders where existing.albums.contains(where: { $0.id == album.id }) {
                try? await photoLibraryService?.removeCollections(
                    [collection], from: existing.collectionList
                )
            }
            if let folder {
                try? await photoLibraryService?.moveCollections(
                    [collection], into: folder.collectionList
                )
            }
            load()
        }
    }

    private var photoLibraryService: PhotoLibraryService? { dependencies?.photoLibrary }

    /// Deletes a user-created smart album and reloads.
    func deleteSmartAlbum(id: String) {
        try? dependencies?.smartAlbumStore.delete(id: id)
        load()
    }

    /// Builds the Memories row. The grouping runs off the main thread: it
    /// walks every located photo twice, which is cheap but not free on a large
    /// library.
    private func loadMemories(libraryQueries: LibraryQueries) async {
        let photos = (try? await libraryQueries.locatedPhotos()) ?? []
        guard !photos.isEmpty else {
            memories = []
            return
        }
        memories = await Task.detached(priority: .utility) {
            MemoryBuilder.memories(
                from: photos,
                trips: TripGrouping.trips(from: photos)
            )
        }.value
    }

    /// Resolves each saved smart album's live count and cover off the main
    /// thread. Both `count` and `gridItems` run on GRDB's reader pool.
    private nonisolated static func loadSmartAlbums(
        smartAlbumStore: SmartAlbumStore,
        libraryQueries: LibraryQueries
    ) async -> [SmartAlbumTokenItem] {
        guard let albums = try? smartAlbumStore.fetchAllOrdered() else { return [] }
        var models: [SmartAlbumTokenItem] = []
        for album in albums {
            let count = (try? await libraryQueries.count(matching: album.query)) ?? 0
            var cover: PHAsset?
            if let firstId = try? await libraryQueries
                .gridItems(matching: album.query, sort: .default, limit: 1)
                .first?.assetId {
                cover = PhotoLibraryService.fetchAssets(ids: [firstId]).first
            }
            models.append(SmartAlbumTokenItem(album: album, count: count, coverAsset: cover))
        }
        return models
    }

    /// One system smart album ShotDex surfaces, with the section it belongs
    /// to and the glyph its token falls back to. Order here is the order the
    /// sections render in.
    private struct SystemAlbumEntry {
        let subtype: PHAssetCollectionSubtype
        let group: AlbumGroup
        let symbolName: String
        /// Overrides PhotoKit's localized title when Photos labels it
        /// differently; `nil` keeps the system name.
        var title: String?
    }

    /// Every system smart album with a public subtype, grouped the way Photos
    /// groups them. Albums that come back empty are dropped by `item(for:)`,
    /// so a library with no panoramas never shows a Panoramas token.
    ///
    /// `.smartAlbumSpatial` is iOS 18, so it is appended conditionally.
    private nonisolated static var systemAlbumCatalog: [SystemAlbumEntry] {
        var entries: [SystemAlbumEntry] = [
            .init(subtype: .smartAlbumRecentlyAdded, group: .suggested, symbolName: "clock"),
            .init(subtype: .smartAlbumFavorites, group: .suggested, symbolName: "heart"),

            .init(subtype: .smartAlbumVideos, group: .mediaType, symbolName: "video"),
            .init(subtype: .smartAlbumSelfPortraits, group: .mediaType, symbolName: "person.crop.square"),
            .init(subtype: .smartAlbumLivePhotos, group: .mediaType, symbolName: "livephoto"),
            .init(subtype: .smartAlbumDepthEffect, group: .mediaType, symbolName: "f.cursive", title: "Portrait"),
            .init(subtype: .smartAlbumPanoramas, group: .mediaType, symbolName: "pano"),
            .init(subtype: .smartAlbumTimelapses, group: .mediaType, symbolName: "timelapse"),
            .init(subtype: .smartAlbumSlomoVideos, group: .mediaType, symbolName: "slowmo"),
            .init(subtype: .smartAlbumCinematic, group: .mediaType, symbolName: "video.badge.waveform"),
            .init(subtype: .smartAlbumBursts, group: .mediaType, symbolName: "square.stack.3d.down.right"),
            .init(subtype: .smartAlbumScreenshots, group: .mediaType, symbolName: "camera.viewfinder"),
            .init(subtype: .smartAlbumScreenRecordings, group: .mediaType, symbolName: "record.circle"),
            .init(subtype: .smartAlbumAnimated, group: .mediaType, symbolName: "square.stack.3d.forward.dottedline"),
            .init(subtype: .smartAlbumLongExposures, group: .mediaType, symbolName: "circle.dashed"),
            .init(subtype: .smartAlbumRAW, group: .mediaType, symbolName: "camera.aperture"),

            // No Hidden album: since iOS 16 the system withholds hidden assets
            // from every app but Photos. Verified on iOS 26 — fetching
            // `.smartAlbumAllHidden` returns an empty result, and a library
            // fetch with `includeHiddenAssets` reports no hidden asset either.
            // Hiding a photo still works; it simply leaves our view of the
            // library for good.
            .init(subtype: .smartAlbumUnableToUpload, group: .utility, symbolName: "exclamationmark.icloud"),
        ]
        if #available(iOS 18.0, *) {
            entries.insert(
                .init(subtype: .smartAlbumSpatial, group: .mediaType, symbolName: "cube.transparent"),
                at: entries.count - 2
            )
        }
        return entries
    }

    private nonisolated static func loadSnapshot() -> Snapshot {
        var result: [AlbumItem] = []

        let imageOptions = PHFetchOptions()
        imageOptions.predicate = PhotoLibraryService.browsableMediaPredicate
        imageOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let onThisDay = OnThisDayModel.fetchAssets(for: .now)

        for entry in Self.systemAlbumCatalog {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: entry.subtype, options: nil
            )
            let options = imageOptions
            collections.enumerateObjects { collection, _, _ in
                if var item = Self.item(for: collection, imageOptions: options) {
                    item.isSmart = true
                    item.group = entry.group
                    item.symbolName = entry.symbolName
                    // The catalog's own name keeps the section in the order and
                    // wording Photos uses even where PhotoKit's localized title
                    // differs ("Recents" vs "Recently Added").
                    if let title = entry.title { item.title = title }
                    result.append(item)
                }
            }
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            if var item = Self.item(for: collection, imageOptions: imageOptions) {
                item.group = item.isShared ? .shared : .user
                result.append(item)
            }
        }

        // Albums that live inside a folder are shown under that folder, not
        // twice — once here and once at the top level.
        let folders = Self.loadFolders(imageOptions: imageOptions)
        let nested = Set(folders.flatMap { $0.albums.map(\.id) })
        result.removeAll { $0.group == .user && nested.contains($0.id) }

        return Snapshot(
            albums: result,
            folders: folders,
            onThisDayCount: onThisDay.count,
            onThisDayCover: onThisDay.firstObject
        )
    }

    /// Leading assets of an album in detail-grid order, for prewarming its
    /// thumbnails before the album is opened. Same options as
    /// `AlbumDetailModel.init`, so the warmed assets are the ones its first
    /// page will ask for.
    nonisolated static func firstAssets(of album: AlbumItem, limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = switch album.kind {
        case .allPhotos: PHAsset.fetchAssets(with: options)
        case .collection(let collection): PHAsset.fetchAssets(in: collection, options: options)
        }
        var assets: [PHAsset] = []
        let upperBound = min(limit, fetch.count)
        assets.reserveCapacity(upperBound)
        for index in 0..<upperBound {
            assets.append(fetch.object(at: index))
        }
        return assets
    }

    private nonisolated static func loadFolders(imageOptions: PHFetchOptions) -> [FolderItem] {
        PhotoLibraryService.fetchFolders().map { list in
            let albums = PhotoLibraryService.fetchChildren(of: list)
                .compactMap { $0 as? PHAssetCollection }
                .compactMap { collection -> AlbumItem? in
                    guard var item = Self.item(for: collection, imageOptions: imageOptions)
                    else { return nil }
                    item.group = item.isShared ? .shared : .user
                    return item
                }
            return FolderItem(collectionList: list, albums: albums)
        }
        // Empty folders are kept, unlike empty media-type albums: the user
        // just made this one, and hiding it until an album moves in would look
        // like the creation failed.
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
final class AlbumDetailModel: PhotoBrowsingSource {
    static let pageSize = 120

    private let metadataStore: MetadataStore
    private let database: AppDatabase
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline
    private let fetchResult: PHFetchResult<PHAsset>
    let sourceAlbum: PHAssetCollection?

    private(set) var photos: [PhotoMetadata] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var hasMorePages = true
    /// Latest in-place deletion, published in the same update as the pruned
    /// list so the grid animates the tiles out instead of reloading.
    private(set) var lastRemoval: PhotoGridRemoval?
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
        self.metadataStore = dependencies.metadataStore
        self.database = dependencies.database
        self.photoLibrary = dependencies.photoLibrary
        self.indexPipeline = dependencies.indexPipeline

        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch album.kind {
        case .allPhotos:
            self.sourceAlbum = nil
            self.fetchResult = PHAsset.fetchAssets(with: options)
        case .collection(let collection):
            self.sourceAlbum = collection.assetCollectionType == .album
                && collection.canPerform(.addContent)
                ? collection
                : nil
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
    /// Takes assets out of this album but leaves them in the library. The grid
    /// prunes exactly like a delete — from this screen's point of view the rows
    /// are gone either way — but the photos and their indexed metadata survive,
    /// so no `metadataStore.deleteAssets` here.
    func removeFromAlbum(ids: Set<String>) async throws {
        guard let sourceAlbum else { return }
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty else { return }
        try await photoLibrary.removeAssets(assets, from: sourceAlbum)
        deletedIds.formUnion(ids)
        lastRemoval = .next(after: lastRemoval, removing: ids)
        photos.removeAll { ids.contains($0.assetId) }
        pageTriggerIds = Set(photos.suffix(30).map(\.assetId))
        for id in ids {
            assetsById.removeValue(forKey: id)
        }
    }

    func deleteAssets(ids: Set<String>) async throws {
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        // PhotoKit is the source of truth; prune the DB rows right away so
        // the grid doesn't show stale entries until the next index run.
        try? metadataStore.deleteAssets(ids: Array(ids))
        deletedIds.formUnion(ids)
        lastRemoval = .next(after: lastRemoval, removing: ids)
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
        try? metadataStore.updateFavorite(assetId: assetId, isFavorite: isFavorite)
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
