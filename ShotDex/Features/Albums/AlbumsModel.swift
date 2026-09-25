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
        /// A capture kind served by ShotDex's own index rather than by a
        /// PhotoKit smart album. Panoramas is the only one today, because it
        /// is the only kind the app itself can create — Photos' Panoramas
        /// album can never hold a photo this app stitched (FS-14 §7).
        case capturedKind(PhotoMediaSubtype)
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
    private var loadedTokens: LibraryChangeTokens?

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
    /// Reloads unless nothing the tab draws has changed since the last one.
    ///
    /// Two tokens, not one. The asset token covers covers and membership; the
    /// collection token covers "an album was created, renamed or deleted",
    /// which moves no asset at all — a brand-new album was invisible here
    /// until the next launch because only the first was watched.
    func load(forChangeTokens tokens: LibraryChangeTokens?) {
        if let tokens, tokens == loadedTokens, !albums.isEmpty { return }
        loadedTokens = tokens
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
            onThisDayCount = snapshot.onThisDayCount
            onThisDayCover = snapshot.onThisDayCover
            if let deps {
                await insertIndexedPanoramas(libraryQueries: deps.libraryQueries)
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

    /// Puts the Panoramas token back into the Media Types row, counted from
    /// ShotDex's index rather than from Photos' album of the same name.
    ///
    /// The index is the only place that knows about a panorama this app
    /// stitched: it has no system pano flag, so Photos files it as an ordinary
    /// photo and its own album would never show it (FS-14 §7).
    ///
    /// Consequence, accepted: on a library that has not been indexed yet the
    /// token is empty and therefore hidden, while the PhotoKit-backed tokens
    /// beside it already have counts. It appears when the index reaches those
    /// photos.
    private func insertIndexedPanoramas(libraryQueries: LibraryQueries) async {
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [.panorama]
        guard let count = try? libraryQueries.count(matching: criteria), count > 0 else { return }
        let coverId = try? await libraryQueries
            .gridItems(matching: criteria, sort: .dateTakenNewest, limit: 1)
            .first?.assetId
        let cover = coverId.flatMap { PhotoLibraryService.fetchAssets(ids: [$0]).first }
        let item = AlbumItem(
            id: "shotdex.capturedKind.panorama",
            title: PhotoMediaSubtype.panorama.title,
            count: count,
            kind: .capturedKind(.panorama),
            coverAsset: cover,
            group: .mediaType,
            symbolName: PhotoMediaSubtype.panorama.systemImage,
            isSmart: true
        )
        // Back where it used to sit, after Portrait, so the row does not
        // reshuffle itself around one token changing source.
        if let portrait = albums.firstIndex(where: {
            $0.group == .mediaType && $0.title == "Portrait"
        }) {
            albums.insert(item, at: albums.index(after: portrait))
        } else if let firstMediaType = albums.firstIndex(where: { $0.group == .mediaType }) {
            albums.insert(item, at: firstMediaType)
        } else {
            albums.append(item)
        }
    }

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
    /// so a library with no screenshots never shows a Screenshots token.
    ///
    /// Panoramas is **not** here. Photos' own Panoramas album can never hold a
    /// photo ShotDex stitched, so that token is built from the index instead
    /// (`indexedPanoramasAlbum`, FS-14 §7).
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
        let fetch: PHFetchResult<PHAsset>
        switch album.kind {
        case .allPhotos:
            fetch = PHAsset.fetchAssets(with: options)
        case .collection(let collection):
            fetch = PHAsset.fetchAssets(in: collection, options: options)
        case .capturedKind:
            // Its photos come from the database, which this synchronous
            // prewarm cannot read. The album opens and warms its own first
            // page instead; the cover is already warm from the token.
            return []
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

    /// The same order expressed for the index, for albums whose photos come
    /// from the database rather than from PhotoKit. "Album Order" has no
    /// meaning there — a query has no arrangement of its own — so it reads as
    /// newest first, which is what the album offers in its place.
    var librarySort: SortOption {
        switch self {
        case .oldestFirst: .dateTakenOldest
        case .albumOrder, .newestFirst: .dateTakenNewest
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
    private let libraryQueries: LibraryQueries?
    /// Where this album's assets come from, in the order they are shown.
    ///
    /// Two shapes because two kinds of album: PhotoKit hands back a live
    /// `PHFetchResult` for a real collection, while a capture kind served by
    /// the index is a list of ids the database ordered — and that order is the
    /// answer, so it is kept rather than handed back to PhotoKit to redo.
    private enum AssetSource {
        case fetch(PHFetchResult<PHAsset>)
        case ordered([PHAsset])

        var count: Int {
            switch self {
            case .fetch(let result): result.count
            case .ordered(let assets): assets.count
            }
        }

        func object(at index: Int) -> PHAsset {
            switch self {
            case .fetch(let result): result.object(at: index)
            case .ordered(let assets): assets[index]
            }
        }
    }

    private var source: AssetSource
    /// True once the index has been asked for a `capturedKind` album's photos,
    /// so an empty answer stays empty instead of being re-queried on every
    /// paging trigger.
    private var hasResolvedIndexedAssets = false
    /// True between asking the index for a list (a capture-kind album's, or an
    /// advanced query's) and the answer arriving.
    private var isAwaitingIndex = false
    /// True once an advanced query's list has been asked for since the last
    /// restart.
    private var hasResolvedAdvanced = false
    /// The album's ids, for counting a query inside it while the Advanced
    /// sheet is being filled. Order does not matter for a count.
    private var cachedAlbumIds: [String]?
    let sourceAlbum: PHAssetCollection?
    /// The album this model is paging, kept so a sort change can re-fetch.
    private let albumKind: AlbumItem.Kind
    private let albumId: String
    private(set) var sortOrder: AlbumSortOrder
    /// What the Filter menu narrows the album to (FS-06.09). Owned by the
    /// screen and handed back when the model is rebuilt, so a library change
    /// does not drop it.
    private(set) var filter: AlbumFilter
    /// The album's size before filtering — the "of 40" in "12 of 40", and
    /// whether the Filter menu has anything to act on.
    private(set) var unfilteredCount = 0
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

    /// Paging cursor into the immutable `source` snapshot. Tracked
    /// separately from `photos.count` because deletions prune `photos`
    /// without shifting the snapshot's indexes.
    private var nextFetchIndex = 0
    /// Deleted asset ids that may still sit in the `source` snapshot;
    /// skipped when later pages reach them.
    private var deletedIds: Set<String> = []

    init(album: AlbumItem, dependencies: AppDependencies, filter: AlbumFilter = AlbumFilter()) {
        self.metadataStore = dependencies.metadataStore
        self.database = dependencies.database
        self.photoLibrary = dependencies.photoLibrary
        self.indexPipeline = dependencies.indexPipeline
        self.libraryQueries = dependencies.libraryQueries
        self.albumKind = album.kind
        self.albumId = album.id
        let order = AlbumSortStore.order(for: album.id, isSmartAlbum: album.isSmart)
        self.sortOrder = order
        self.filter = filter

        switch album.kind {
        case .allPhotos:
            self.sourceAlbum = nil
        case .collection(let collection):
            self.sourceAlbum = collection.assetCollectionType == .album
                && collection.canPerform(.addContent)
                ? collection
                : nil
        case .capturedKind:
            // A query, not a container: nothing can be added to it.
            self.sourceAlbum = nil
        }
        self.source = .ordered([])
        self.source = makeSource()
        self.unfilteredCount = countUnfiltered()
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
        restart()
    }

    /// Narrows the album and starts its paging again from the top.
    func setFilter(_ newValue: AlbumFilter) {
        guard newValue != filter else { return }
        filter = newValue
        restart()
    }

    /// Rebuilds the source for the current order and filter and pages from
    /// the top. The content version tells the grid the list is a new list,
    /// which a same-count re-sort would not otherwise say.
    private func restart() {
        source = makeSource()
        hasResolvedIndexedAssets = false
        hasResolvedAdvanced = false
        photos = []
        assetsById = [:]
        pageTriggerIds = []
        nextFetchIndex = 0
        hasMorePages = true
        lastRemoval = nil
        deletedIds = []
        contentVersion += 1
        loadNextPage()
    }

    /// The Photos fetch for the current order, narrowed by the quick filters
    /// Photos can answer itself. A capture-kind album's list comes from the
    /// index instead and resolves on first page.
    private func makeSource() -> AssetSource {
        // An advanced query is answered by the index: the list arrives on the
        // first page, like a capture-kind album's.
        if filter.advancedQuery != nil { return .ordered([]) }
        let criteria = filter.criteria
        var stitched: [String] = []
        if criteria.mediaSubtypes.contains(.panorama) {
            stitched = (try? libraryQueries?.stitchedPanoramaIds()) ?? []
        }
        let predicate = AlbumFilterPredicate.predicate(for: criteria, stitchedPanoramaIds: stitched)
        return Self.fetch(kind: albumKind, order: sortOrder, filter: predicate)
    }

    private func countUnfiltered() -> Int {
        switch albumKind {
        case .capturedKind(let subtype):
            var criteria = FilterCriteria()
            criteria.mediaSubtypes = [subtype]
            return (try? libraryQueries?.count(matching: criteria)) ?? 0
        default:
            guard filter.isActive else { return source.count }
            return Self.fetch(kind: albumKind, order: sortOrder, filter: nil).count
        }
    }

    /// Of `ids`, the ones the current filter still shows — how a selection
    /// sheds the photos a new filter hides (FS-01.06 §2). Asks Photos for just
    /// those ids rather than walking the whole album.
    ///
    /// Nil while a capture-kind album is still waiting on the index: the list
    /// is not known yet, and an empty answer would clear the selection.
    func matchingIds(among ids: [String]) -> Set<String>? {
        guard !ids.isEmpty else { return [] }
        if isAwaitingIndex { return nil }
        if case .capturedKind = albumKind, !hasResolvedIndexedAssets { return nil }
        if filter.advancedQuery != nil, !hasResolvedAdvanced { return nil }
        switch source {
        case .ordered(let assets):
            let wanted = Set(ids)
            return Set(assets.lazy.map(\.localIdentifier).filter { wanted.contains($0) })
        case .fetch:
            let narrowed = Self.fetch(
                kind: albumKind,
                order: sortOrder,
                filter: AlbumFilterPredicate.predicate(
                    for: filter.criteria,
                    stitchedPanoramaIds: filter.criteria.mediaSubtypes.contains(.panorama)
                        ? ((try? libraryQueries?.stitchedPanoramaIds()) ?? [])
                        : []
                ),
                restrictedTo: ids
            )
            var result = Set<String>()
            if case .fetch(let fetched) = narrowed {
                fetched.enumerateObjects { asset, _, _ in result.insert(asset.localIdentifier) }
            }
            return result.subtracting(deletedIds)
        }
    }

    private nonisolated static func fetch(
        kind: AlbumItem.Kind,
        order: AlbumSortOrder,
        filter: NSPredicate?,
        restrictedTo ids: [String]? = nil
    ) -> AssetSource {
        let options = PHFetchOptions()
        var predicates = [PhotoLibraryService.browsableMediaPredicate]
        if let filter { predicates.append(filter) }
        if let ids { predicates.append(NSPredicate(format: "localIdentifier IN %@", ids)) }
        options.predicate = predicates.count == 1
            ? predicates[0]
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = order.sortDescriptors
        switch kind {
        case .allPhotos:
            // All Photos has no arrangement of its own; unsorted there is
            // whatever order PhotoKit happens to hand back.
            options.sortDescriptors = order.sortDescriptors
                ?? [NSSortDescriptor(key: "creationDate", ascending: false)]
            return .fetch(PHAsset.fetchAssets(with: options))
        case .collection(let collection):
            return .fetch(PHAsset.fetchAssets(in: collection, options: options))
        case .capturedKind:
            // Nothing to fetch yet: the list comes from the database, which
            // cannot be read synchronously here. `loadNextPage` resolves it on
            // first use and calls back in.
            return .ordered([])
        }
    }

    var totalCount: Int { source.count }

    func loadNextPage() {
        guard hasMorePages else { return }
        if case .capturedKind(let subtype) = albumKind, !hasResolvedIndexedAssets {
            resolveIndexedAssets(for: subtype)
            return
        }
        if filter.advancedQuery != nil, !hasResolvedAdvanced {
            if case .capturedKind = albumKind {} else {
                resolveAdvancedAssets()
                return
            }
        }
        let start = nextFetchIndex
        let end = min(start + Self.pageSize, source.count)
        guard start < end else {
            hasMorePages = false
            return
        }

        var pageAssets: [PHAsset] = []
        pageAssets.reserveCapacity(end - start)
        for index in start..<end {
            let asset = source.object(at: index)
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
        hasMorePages = nextFetchIndex < source.count
        pageTriggerIds = Set(photos.suffix(30).map(\.assetId))
    }

    /// Asks the index which photos are this capture kind, then turns those ids
    /// into assets **once**, keeping the database's order.
    ///
    /// The order is the database's rather than PhotoKit's on purpose: a fetch
    /// by identifiers does not promise to come back in the order it was asked,
    /// and this list is already sorted by the column the user picked.
    private func resolveIndexedAssets(for subtype: PhotoMediaSubtype) {
        hasResolvedIndexedAssets = true
        guard let libraryQueries else { return }
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [subtype]
        let sort = sortOrder.librarySort
        let narrowing: LibraryQueries.IndexFilter = filter.advancedQuery.map { .query($0) }
            ?? .criteria(filter.criteria)
        let requestedFilter = filter
        isAwaitingIndex = true
        Task { [weak self] in
            let ids = (try? await libraryQueries.gridItems(
                matchingAll: [.criteria(criteria), narrowing],
                sort: sort
            ))?.map(\.assetId) ?? []
            // A newer filter or order has started its own lookup.
            guard let self, self.filter == requestedFilter, self.sortOrder.librarySort == sort else { return }
            let byId = PhotoLibraryService.fetchAssets(ids: ids)
                .reduce(into: [String: PHAsset]()) { $0[$1.localIdentifier] = $1 }
            // Ids the library no longer has simply drop out — the index can be
            // a moment behind a deletion.
            self.isAwaitingIndex = false
            self.source = .ordered(ids.compactMap { byId[$0] })
            self.loadNextPage()
        }
    }

    /// An album's Advanced Filter (FS-06.09): the album's ids in its current
    /// order, the index asked which of those match, and the album's order
    /// kept — so Album Order still means the album's own arrangement.
    private func resolveAdvancedAssets() {
        hasResolvedAdvanced = true
        guard let libraryQueries, let advanced = filter.advancedQuery else { return }
        isAwaitingIndex = true
        let kind = albumKind
        let order = sortOrder
        let requestedFilter = filter
        Task { [weak self] in
            let ids = await Task.detached(priority: .userInitiated) {
                Self.orderedIds(kind: kind, order: order)
            }.value
            let matching = Set((try? await libraryQueries.gridItems(
                matchingAll: [.query(advanced)],
                restrictedTo: ids,
                sort: .default
            ))?.map(\.assetId) ?? [])
            // A newer filter or order has started its own lookup.
            guard let self, self.filter == requestedFilter, self.sortOrder == order else { return }
            let kept = ids.filter(matching.contains)
            let byId = PhotoLibraryService.fetchAssets(ids: kept)
                .reduce(into: [String: PHAsset]()) { $0[$1.localIdentifier] = $1 }
            self.cachedAlbumIds = ids
            self.isAwaitingIndex = false
            self.source = .ordered(kept.compactMap { byId[$0] })
            self.loadNextPage()
        }
    }

    /// How many of the album's photos a query matches — the Advanced sheet's
    /// live count, inside the album rather than across the library.
    func countMatching(_ query: SmartAlbumQuery) async -> Int {
        guard let libraryQueries else { return 0 }
        if case .capturedKind(let subtype) = albumKind {
            var criteria = FilterCriteria()
            criteria.mediaSubtypes = [subtype]
            return (try? await libraryQueries.count(matchingAll: [.criteria(criteria), .query(query)])) ?? 0
        }
        let ids: [String]
        if let cachedAlbumIds {
            ids = cachedAlbumIds
        } else {
            let kind = albumKind
            let order = sortOrder
            ids = await Task.detached(priority: .userInitiated) {
                Self.orderedIds(kind: kind, order: order)
            }.value
            cachedAlbumIds = ids
        }
        return (try? await libraryQueries.count(matchingAll: [.query(query)], restrictedTo: ids)) ?? 0
    }

    /// Every id in the album, in display order. Walks the whole fetch, so it
    /// runs off the main thread.
    private nonisolated static func orderedIds(kind: AlbumItem.Kind, order: AlbumSortOrder) -> [String] {
        guard case .fetch(let result) = fetch(kind: kind, order: order, filter: nil) else { return [] }
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
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
        unfilteredCount = max(0, unfilteredCount - ids.count)
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
        unfilteredCount = max(0, unfilteredCount - ids.count)
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
