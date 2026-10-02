import Foundation

/// What Delete Rejected deletes (FS-01.12b §3): the Rejected photos **in
/// the set on screen** — the pass's photos, or the grid as filtered —
/// never Rejected photos anywhere else. The same rule as "Delete never
/// touches what you cannot see" (FS-01.06). Pure.
enum RejectedDeletion {
    /// `visible` ∩ Rejected, in `visible`'s order.
    static func ids(visible: [String], flag: (String) -> PhotoFlag?) -> [String] {
        visible.filter { flag($0) == .reject }
    }

    /// The pill shows only while the quick filter Rejected is on — not for
    /// a flag condition in Advanced Filter (plan §9).
    static func showsPill(for criteria: FilterCriteria) -> Bool {
        criteria.flags.contains(.rejected)
    }
}
