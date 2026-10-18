import Foundation
import Photos

/// What one write to Photos changed on each asset: its modification date
/// before and after. Photos moves the date when a property really changes
/// (FS-01.12 §10, M1) — a rating, a favorite — so the caller re-stamps the
/// index with the new date, or the next index run would take the write for
/// an edit and read every file again.
struct PropertyWriteResult: Equatable, Sendable {
    struct Dates: Equatable, Sendable {
        var before: Int?
        var after: Int?
    }

    var dates: [String: Dates]
    /// Ids Photos would not let the app change (`canPerform(.properties)`
    /// is false — a shared library or shared album asset). Left out of the
    /// write; the caller says so (FS-02.07 §6).
    var refused: Set<String> = []

    static let empty = PropertyWriteResult(dates: [:])
}

/// Writes ShotDex's own properties into Photos — **one** `performChanges` per
/// command, however many photos it covers, so Photos sends one library change
/// (FS-01.12 §5). Shared with FS-02.07 (caption and keywords), which adds its
/// methods here. The PhotoKit version needs iOS 27; tests use a fake that
/// counts blocks and requests.
protocol PhotoPropertyWriting: Sendable {
    /// Sets the star rating (0 = unset) of every id that still exists.
    func setRating(_ rating: Int, ids: [String]) async throws -> PropertyWriteResult

    /// Sets each id to its own rating, still in one block — the star
    /// migration and undo write mixed values.
    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult

    /// Applies each asset's caption and keyword change in **one**
    /// `performChanges` (FS-02.07 §5) — keywords added and removed one by
    /// one, the caption set or cleared only when the change says so. An asset
    /// that refuses property edits is skipped and reported in `refused`; one
    /// that no longer exists is skipped silently. Never touches a resource,
    /// so nothing is downloaded (AC-12).
    func applyCaptionKeywords(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult
}

extension PhotoPropertyWriting {
    func setRating(_ rating: Int, ids: [String]) async throws -> PropertyWriteResult {
        try await setRatings(Dictionary(uniqueKeysWithValues: ids.map { ($0, rating) }))
    }

    /// Writers that predate caption and keywords (the rating fakes) refuse.
    func applyCaptionKeywords(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult {
        throw CocoaError(.featureUnsupported)
    }
}

@available(iOS 27, macOS 27, *)
struct PhotoKitPropertyWriter: PhotoPropertyWriting {
    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult {
        guard !ratings.isEmpty else { return .empty }
        let assets = PhotoLibraryService.fetchAssets(ids: Array(ratings.keys))
        guard !assets.isEmpty else { return .empty }
        let before = Self.modificationDates(assets)
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                let stars = StarRating.clamped(ratings[asset.localIdentifier] ?? 0)
                PHAssetChangeRequest(for: asset).rating = PHAsset.Rating(rawValue: stars) ?? .unset
            }
        }
        let after = Self.modificationDates(PhotoLibraryService.fetchAssets(ids: assets.map(\.localIdentifier)))
        var dates: [String: PropertyWriteResult.Dates] = [:]
        for (id, date) in before {
            dates[id] = PropertyWriteResult.Dates(before: date, after: after[id] ?? date)
        }
        return PropertyWriteResult(dates: dates)
    }

    func applyCaptionKeywords(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult {
        let wanted = changes.filter { !$0.value.isEmpty }
        guard !wanted.isEmpty else { return .empty }
        let found = PhotoLibraryService.fetchAssets(ids: Array(wanted.keys))
        let assets = found.filter { $0.canPerform(.properties) }
        let refused = Set(found.map(\.localIdentifier)).subtracting(assets.map(\.localIdentifier))
        guard !assets.isEmpty else { return PropertyWriteResult(dates: [:], refused: refused) }
        let before = Self.modificationDates(assets)
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                guard let change = wanted[asset.localIdentifier] else { continue }
                let request = PHAssetChangeRequest(for: asset)
                for keyword in change.remove { request.removeKeyword(keyword) }
                for keyword in change.add { request.addKeyword(keyword) }
                switch change.caption {
                case .untouched: break
                case .set(let text): request.caption = text
                // Measured on iOS 27.0 (FS-02.07 §10 q5): `nil` leaves the
                // caption in place, only the empty string clears it.
                case .clear: request.caption = ""
                }
            }
        }
        let after = Self.modificationDates(PhotoLibraryService.fetchAssets(ids: assets.map(\.localIdentifier)))
        var dates: [String: PropertyWriteResult.Dates] = [:]
        for (id, date) in before {
            dates[id] = PropertyWriteResult.Dates(before: date, after: after[id] ?? date)
        }
        return PropertyWriteResult(dates: dates, refused: refused)
    }

    private static func modificationDates(_ assets: [PHAsset]) -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: assets.map {
            ($0.localIdentifier, $0.modificationDate.map { Int($0.timeIntervalSince1970) })
        })
    }
}

#if DEBUG
/// `-ShotDexRefuseProperties <n>`: Photos "refuses" the first n photos of
/// every caption/keyword write (sorted by id) the way a shared-library asset
/// would, so the "4 photos can't be changed." banner can be seen on a
/// simulator, which has no shared library (FS-02.07 AC-13).
struct RefusingPropertyWriter: PhotoPropertyWriting {
    static let launchArgument = "-ShotDexRefuseProperties"
    let base: any PhotoPropertyWriting
    let count: Int

    static func count(in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: launchArgument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
    }

    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult {
        try await base.setRatings(ratings)
    }

    func applyCaptionKeywords(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult {
        let refused = Set(changes.keys.sorted().prefix(count))
        var result = try await base.applyCaptionKeywords(changes.filter { !refused.contains($0.key) })
        result.refused.formUnion(refused)
        return result
    }
}

/// `-ShotDexFailRatingWrites`: every write is refused, so the "Couldn't save
/// rating." path can be seen on a simulator (FS-01.12 AC-10).
struct FailingPropertyWriter: PhotoPropertyWriting {
    static let launchArgument = "-ShotDexFailRatingWrites"

    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult {
        try await Task.sleep(for: .milliseconds(300))
        throw CocoaError(.fileWriteUnknown)
    }
}
#endif
