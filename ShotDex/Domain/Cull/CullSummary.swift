import Foundation

/// The counts the culling pass shows at its end and in its top bar
/// (FS-01.12b §2): `240 photos · 52 picks · 120 rejected · 68 unflagged`.
struct CullSummary: Equatable, Sendable {
    let total: Int
    let picks: Int
    let rejected: Int

    var unflagged: Int { total - picks - rejected }

    init(ids: [String], flag: (String) -> PhotoFlag?) {
        var picks = 0
        var rejected = 0
        for id in ids {
            switch flag(id) {
            case .pick: picks += 1
            case .reject: rejected += 1
            case nil: break
            }
        }
        self.total = ids.count
        self.picks = picks
        self.rejected = rejected
    }

    /// The ids still without a flag, in pass order — Review Unflagged.
    static func unflaggedIds(_ ids: [String], flag: (String) -> PhotoFlag?) -> [String] {
        ids.filter { flag($0) == nil }
    }

    /// The ids flagged Reject, in pass order — Delete N Rejected….
    static func rejectedIds(_ ids: [String], flag: (String) -> PhotoFlag?) -> [String] {
        ids.filter { flag($0) == .reject }
    }
}
