import Foundation
import Photos

/// What a sidebar place shows before any filter (Mac sidebar, FS-18.01 §2):
/// the base the grid's own filters narrow. Read off the main actor — the
/// Recently Added fetch and the index reads run on GRDB's pool or a detached
/// task, never while a click waits.
enum LibraryPlace: Equatable, Sendable {
    /// Rules the index answers: Favorites, Videos, RAW, one source.
    case rules(SmartAlbumQuery)
    /// Photos' own Recently Added album, plus folder, drive and server photos
    /// indexed in the last 30 days. `indexedAt` is the last read, so a file
    /// re-read after an edit counts as added again — close enough for files,
    /// which carry no "added" date of their own.
    case recentlyAdded
    /// Photos taken on this month and day in earlier years (FS-06.07).
    case onThisDay(month: Int, day: Int)
    /// One of Photos' albums, opened from Collections (Mac FS-18.04 §1).
    case album(String)
    /// Photos the subject scan found a face in — People and Pets' People.
    case people
    /// Photos with a cat or a dog in them.
    case pets

    #if DEBUG
    /// A library that is not Photos (the Mac's demo) answers albums itself.
    /// Set once at launch, before any place is read.
    nonisolated(unsafe) static var albumAssetIds: ((String) -> [String]?)?
    #endif

    static let favorites = LibraryPlace.rules(SmartAlbumQuery(rules: [SmartAlbumRule(field: .favorite, boolValue: true)]))
    static let videos = LibraryPlace.rules(SmartAlbumQuery(rules: [
        SmartAlbumRule(field: .mediaType, op: .isExactly, text: MediaKind.video.rawValue),
    ]))
    static let raw = LibraryPlace.rules(SmartAlbumQuery(rules: [
        SmartAlbumRule(field: .fileType, op: .isExactly, text: PhotoFileType.raw.rawValue),
    ]))

    static func source(_ id: String) -> LibraryPlace {
        .rules(SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: .isExactly, text: id)]))
    }

    /// How far back Recently Added reaches for photos outside Photos — the
    /// window Photos' own album uses.
    static let recentWindow: TimeInterval = 30 * 24 * 3600

    /// The order the place always shows, whatever the Library's sort: On
    /// This Day's year sections need date order (FS-06.07 §4).
    var fixedSort: SortOption? {
        if case .onThisDay = self { return .dateTakenNewest }
        return nil
    }

    /// The place's conditions as index filters.
    func filters() async throws -> [LibraryQueries.IndexFilter] {
        switch self {
        case .rules(let query): [.query(query)]
        case .recentlyAdded, .onThisDay, .album, .people, .pets: []
        }
    }

    /// The ids the place is restricted to, or nil for no restriction.
    func assetIds(queries: LibraryQueries, now: Date = Date()) async throws -> [String]? {
        switch self {
        case .rules:
            return nil
        case .onThisDay(let month, let day):
            return try await queries.assetIdsOnThisDay(month: month, day: day, now: now)
        case .album(let id):
            #if DEBUG
            if let ids = Self.albumAssetIds?(id) { return ids }
            #endif
            return await Task.detached(priority: .userInitiated) { PhotoLibraryService.assetIds(inAlbum: id) }.value
        case .people:
            return try await queries.assetIdsWithFaces()
        case .pets:
            return try await queries.assetIdsWithAnimals()
        case .recentlyAdded:
            let fromPhotos = await Task.detached(priority: .userInitiated) { Self.photosRecentlyAdded() }.value
            let fromFiles = try await queries.assetIdsOutsidePhotos(indexedSince: now.addingTimeInterval(-Self.recentWindow))
            return fromPhotos + fromFiles
        }
    }

    private static func photosRecentlyAdded() -> [String] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite).canReadLibrary,
              let album = PHAssetCollection.fetchAssetCollections(
                  with: .smartAlbum, subtype: .smartAlbumRecentlyAdded, options: nil
              ).firstObject
        else { return [] }
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }
}

private extension PHAuthorizationStatus {
    var canReadLibrary: Bool { self == .authorized || self == .limited }
}
