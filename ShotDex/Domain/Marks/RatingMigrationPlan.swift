import Foundation

/// The one-time move of pending stars into Photos on the first launch under
/// iOS 27 (FS-01.12 §5), decided without touching PhotoKit: what to write,
/// which rows to drop, which to keep. Pure — `RatingMigrationPlanTests`.
struct RatingMigrationPlan: Equatable, Sendable {
    /// Photo → stars to write, all in one block.
    var writes: [String: Int] = [:]
    /// Rows dropped without a write: Photos already holds a rating for the
    /// photo (the user may have rated it on a Mac since — theirs wins), or
    /// the pending row is a 0 Photos already agrees with.
    var droppedForPhotos: [String] = []
    /// Rows of photos that are gone. Only ever filled with full access.
    var droppedAsDeleted: [String] = []
    /// Rows left for a later launch: under `.limited`, photos not shared
    /// with the app are not known to be gone.
    var kept: [String] = []

    /// Rows to delete once the write succeeded.
    var rowsToDelete: [String] { Array(writes.keys) + droppedForPhotos + droppedAsDeleted }

    var isEmpty: Bool { writes.isEmpty && droppedForPhotos.isEmpty && droppedAsDeleted.isEmpty }

    /// - Parameters:
    ///   - pending: every row of `pending_photo_rating`.
    ///   - photosRatings: `PHAsset.rating` of the photos PhotoKit returned
    ///     for those ids — the ones that exist *and* are visible.
    ///   - accessIsFull: whether a missing id means deleted.
    static func make(pending: [PendingRating], photosRatings: [String: Int], accessIsFull: Bool) -> RatingMigrationPlan {
        var plan = RatingMigrationPlan()
        for row in pending {
            guard let photos = photosRatings[row.assetId] else {
                if accessIsFull {
                    plan.droppedAsDeleted.append(row.assetId)
                } else {
                    plan.kept.append(row.assetId)
                }
                continue
            }
            if photos != 0 || row.rating == 0 {
                plan.droppedForPhotos.append(row.assetId)
            } else {
                plan.writes[row.assetId] = StarRating.clamped(row.rating)
            }
        }
        return plan
    }
}
