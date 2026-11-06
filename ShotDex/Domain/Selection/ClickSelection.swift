import Foundation

/// Pointer selection as Finder does it, over items in one drawing order: a
/// plain click picks one item; ⌘-click adds or removes one; ⇧-click picks the
/// run from the anchor — the last item clicked without ⇧ — to the item, and
/// ⌘⇧-click adds that run to what is picked. Pure; the Mac server browser's
/// grid, columns and list use it (FS-19.08 §3).
struct ClickSelection: Equatable, Sendable {
    private(set) var ids: Set<String> = []
    private(set) var anchor: String?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// A click on `id`; `order` is every item in drawing order. An anchor no
    /// longer in `order` makes a ⇧-click a plain one.
    mutating func click(_ id: String, in order: [String], extendsSelection: Bool, extendsRange: Bool) {
        if extendsRange, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            let run = Set(order[min(from, to)...max(from, to)])
            ids = extendsSelection ? ids.union(run) : run
            return
        }
        if extendsSelection {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        } else {
            ids = [id]
        }
        anchor = id
    }

    /// A selection made elsewhere (a table's own ⌘/⇧ handling, a launch
    /// argument). As in NSTableView, the anchor stays where it is while it
    /// is still picked; otherwise it moves to the first picked item in
    /// `order`.
    mutating func replace(with newIds: Set<String>, in order: [String]) {
        ids = newIds
        if let anchor, newIds.contains(anchor) { return }
        anchor = order.first { newIds.contains($0) }
    }

    /// Drops whatever is no longer drawn — after a search or a rescan.
    mutating func prune(to order: [String]) {
        let present = Set(order)
        ids.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
    }

    mutating func clear() {
        ids = []
        anchor = nil
    }
}
