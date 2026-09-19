import Foundation

/// Lightroom's pick / reject flag. PhotoKit has nothing like it — `isFavorite`
/// is one bit and it is already spoken for — so this is ShotDex's own data.
enum PhotoFlag: Int, Codable, CaseIterable, Identifiable, Sendable {
    case unflagged = 0
    case picked = 1
    case rejected = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unflagged: "Unflagged"
        case .picked: "Pick"
        case .rejected: "Reject"
        }
    }

    var systemImage: String {
        switch self {
        case .unflagged: "flag.slash"
        case .picked: "flag.fill"
        case .rejected: "xmark.bin"
        }
    }
}

/// What culling records about one photo: how good it is, and whether it is in
/// or out.
///
/// Kept out of `PhotoMetadata` on purpose. The indexer upserts a whole metadata
/// row on every pass, so a column it does not know about is blanked each
/// re-index — the same reason `perceptual_hash` and `subject_scan` have tables
/// of their own. This is the one kind of data in the app the *user* typed, and
/// losing it to a background index run would be unforgivable.
struct PhotoCullState: Equatable, Sendable {
    var assetId: String
    /// 0–5, where 0 means unrated. Lightroom's scale, and the one every
    /// photographer already has in their fingers.
    var rating: Int
    var flag: PhotoFlag

    init(assetId: String, rating: Int = 0, flag: PhotoFlag = .unflagged) {
        self.assetId = assetId
        self.rating = Self.clampedRating(rating)
        self.flag = flag
    }

    var isEmpty: Bool { rating == 0 && flag == .unflagged }

    /// Ratings arrive from taps on a five-star row and from a smart-album rule,
    /// so they are clamped in one place rather than at each call site.
    static func clampedRating(_ value: Int) -> Int {
        min(5, max(0, value))
    }

    static let ratingRange = 0...5
}
