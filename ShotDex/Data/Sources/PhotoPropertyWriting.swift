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
}

extension PhotoPropertyWriting {
    func setRating(_ rating: Int, ids: [String]) async throws -> PropertyWriteResult {
        try await setRatings(Dictionary(uniqueKeysWithValues: ids.map { ($0, rating) }))
    }
}

@available(iOS 27, *)
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

    private static func modificationDates(_ assets: [PHAsset]) -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: assets.map {
            ($0.localIdentifier, $0.modificationDate.map { Int($0.timeIntervalSince1970) })
        })
    }
}

#if DEBUG
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
