import Foundation

/// The keep-or-drop decision of a culling pass (FS-01.12 §2). Three states,
/// mutually exclusive: Pick, Reject, or no flag — the last is `nil`, never a
/// third case, so "has a flag" is a plain optional test.
///
/// Raw values are what `photo_flag.flag` stores and what a smart album's
/// JSON carries, so the two can never spell the same flag two ways.
enum PhotoFlag: String, Codable, CaseIterable, Sendable {
    case pick
    case reject
}

/// Star ratings, 0–5. Zero means "not rated", the same value Photos' own
/// `PHAsset.Rating.unset` has, so one number travels both ways.
enum StarRating {
    static let range = 0...5

    static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The Rating ▸ submenu of the filter menu (FS-01.12 §7): Any is `nil` on
/// `FilterCriteria`, so this holds only the two choices that constrain.
enum RatingFilter: Hashable, Codable, Sendable {
    /// ★ & Up … ★★★★★ — the current rating is at least this many stars.
    case atLeast(Int)
    /// No stars.
    case unrated

    /// The choices the submenu lists after Any, in order.
    static let menuChoices: [RatingFilter] = [.atLeast(1), .atLeast(2), .atLeast(3), .atLeast(4), .atLeast(5), .unrated]

    func matches(_ rating: Int) -> Bool {
        switch self {
        case .atLeast(let stars): rating >= stars
        case .unrated: rating == 0
        }
    }
}

/// The flag rows of the filter menu (Picks, Rejected) plus Unflagged, which
/// only a chip or Advanced Filter can set. Several on means any of them.
enum PhotoFlagFilter: String, Codable, CaseIterable, Hashable, Sendable {
    case picks
    case rejected
    case unflagged

    func matches(_ flag: PhotoFlag?) -> Bool {
        switch self {
        case .picks: flag == .pick
        case .rejected: flag == .reject
        case .unflagged: flag == nil
        }
    }
}

/// One photo's marks as the viewer and VoiceOver read them.
struct PhotoMarkSummary: Equatable, Sendable {
    var rating: Int
    var flag: PhotoFlag?

    var isEmpty: Bool { rating == 0 && flag == nil }
}
