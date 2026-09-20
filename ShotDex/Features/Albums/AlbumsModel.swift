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

    /// The PhotoKit collection behind this row, or nil for All Photos, which
    /// is a fetch rather than an album and cannot be added to.
    var assetCollection: PHAssetCollection? {
        guard case .collection(let collection) = kind else { return nil }
        return collection
    }
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
            creationCount = (try? deps?.creations.count()) ?? 0
            onThisDayCount = snapshot.onThisDayCount
            onThisDayCover = snapshot.onThisDayCover
            if let deps {
                smartQueryAlbums = await Self.loadSmartAlbums(
                    smartAlbumStore: deps.smartAlbumStore,
                    libraryQueries: deps.libraryQueries
                )
                await loadMemories(libraryQueries: deps.libraryQueries)
                await loadSubjects(libraryQueries: deps.libraryQueries)
            }
            isLoading = false
        }
    }

    /// How many collages and videos ShotDex has made. Drives whether the
    /// Creations row appears at all — an empty Creations screen is a row that
    /// only ever says "no".
    private(set) var creationCount = 0
    /// Auto-curated collections for the Memories row.
    private(set) var memories: [Memory] = []
    /// Photos the opt-in subject scan found faces in. Empty until the user
    /// runs that scan from Settings, which is when the People token appears.
    private(set) var peopleAssetIds: [String] = []
    /// Photos that scan found a cat or a dog in.
    private(set) var petAssetIds: [String] = []

    // MARK: Album lifecycle

    func createAlbum(named name: String) {
        Task {
            _ = try? await photoLibraryService?.createAlbum(named: name)
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

    /// Reads the two subject collections. Both are plain indexed reads of a
    /// column the scan filled — no Vision work happens here.
    private func loadSubjects(libraryQueries: LibraryQueries) async {
        peopleAssetIds = (try? await libraryQueries.assetIdsWithFaces()) ?? []
        petAssetIds = (try? await libraryQueries.assetIdsWithAnimals()) ?? []
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
            //
            // No Recently Deleted either, and this one is not a permission
            // wall but a missing API: `PHAssetCollectionSubtype` runs
            // 200…220 and has no case for it (checked against the iOS 26.1
            // SDK's `PhotosTypes.h`). There is no public way to list, count
            // or restore a trashed asset, and no documented URL that opens
            // Photos on that album. Our own delete does say where the photos
            // go — see the Duplicates screen's "Photos move to Recently
            // Deleted" — and that is as close as a third-party app gets.
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

        // Albums nested in a Photos folder are listed here like any other,
        // not under a heading of their own: the tab shows albums, and a
        // second level of containers to open first is a level of nothing.
        return Snapshot(
            albums: result,
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

/// How an album's photos are ordered on screen.
///
/// `albumOrder` is the album's own arrangement — the order photos were added,
/// or the order the user dragged them into in Photos. PhotoKit gives it by
/// asking for no sort at all, which is why it is not just another descriptor.
enum AlbumSortOrder: String, CaseIterable, Identifiable, Sendable {
    case albumOrder
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albumOrder: "Album Order"
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }

    var systemImage: String {
        switch self {
        case .albumOrder: "list.number"
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }

    var sortDescriptors: [NSSortDescriptor]? {
        switch self {
        case .albumOrder: nil
        case .newestFirst: [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .oldestFirst: [NSSortDescriptor(key: "creationDate", ascending: true)]
        }
    }
}

/// Remembers the order each album was last browsed in.
///
/// Per album, not one setting for all of them: a trip album reads in the order
/// it happened, a wallpapers album in the order things were added, and one
/// global switch would make the user re-pick every time they moved between the
/// two.
enum AlbumSortStore {
    private static let key = "albums.sortOrder"

    static func order(for albumId: String, isSmartAlbum: Bool) -> AlbumSortOrder {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        if let raw = stored?[albumId], let order = AlbumSortOrder(rawValue: raw) {
            return order
        }
        // A smart album has no arrangement of its own to fall back on.
        return isSmartAlbum ? .newestFirst : .albumOrder
    }

    static func setOrder(_ order: AlbumSortOrder, for albumId: String) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[albumId] = order.rawValue
        UserDefaults.standard.set(stored, forKey: key)
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
    private var fetchResult: PHFetchResult<PHAsset>
    let sourceAlbum: PHAssetCollection?
    /// The album this model is paging, kept so a sort change can re-fetch.
    private let albumKind: AlbumItem.Kind
    private let albumId: String
    private(set) var sortOrder: AlbumSortOrder
    /// Bumped when the order changes. The grid reloads on a content-version
    /// change; a re-sort keeps the same photos and the same count, so nothing
    /// else would tell it the list it is showing is no longer the list.
    private(set) var contentVersion = 0

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
        self.albumKind = album.kind
        self.albumId = album.id
        let order = AlbumSortStore.order(for: album.id, isSmartAlbum: album.isSmart)
        self.sortOrder = order

        switch album.kind {
        case .allPhotos:
            self.sourceAlbum = nil
        case .collection(let collection):
            self.sourceAlbum = collection.assetCollectionType == .album
                && collection.canPerform(.addContent)
                ? collection
                : nil
        }
        self.fetchResult = Self.fetch(kind: album.kind, order: order)
    }

    /// Whether this album has an arrangement of its own to offer. A smart
    /// album is a query, so "Album Order" would mean nothing there.
    var supportsAlbumOrder: Bool {
        if case .collection(let collection) = albumKind {
            return collection.assetCollectionType == .album
        }
        return false
    }

    /// Re-orders the album and starts its paging again from the top.
    func setSortOrder(_ order: AlbumSortOrder) {
        guard order != sortOrder else { return }
        sortOrder = order
        AlbumSortStore.setOrder(order, for: albumId)
        fetchResult = Self.fetch(kind: albumKind, order: order)
        photos = []
        assetsById = [:]
        pageTriggerIds = []
        nextFetchIndex = 0
        hasMorePages = true
        lastRemoval = nil
        contentVersion += 1
        loadNextPage()
    }

    private nonisolated static func fetch(
        kind: AlbumItem.Kind,
        order: AlbumSortOrder
    ) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = order.sortDescriptors
        switch kind {
        case .allPhotos:
            // All Photos has no arrangement of its own; unsorted there is
            // whatever order PhotoKit happens to hand back.
            options.sortDescriptors = order.sortDescriptors
                ?? [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(with: options)
        case .collection(let collection):
            return PHAsset.fetchAssets(in: collection, options: options)
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
