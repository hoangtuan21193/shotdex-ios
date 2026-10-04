import Foundation

/// What the shared preview cache gives up first when it passes its limit
/// (FS-19 01b §5): full-size previews, longest unopened first, and only
/// once none are left, thumbnails used longest ago. A thumbnail is 40 KB and
/// may belong to a drive that is unplugged — it cannot be made again until
/// the drive comes back; a 2400px preview can be redrawn from any thumbnail's
/// source the next time it is opened.
enum PreviewCacheEviction {
    enum Kind: Sendable {
        case thumbnail
        case preview
    }

    struct Item: Equatable, Sendable {
        let url: URL
        let kind: Kind
        let size: Int64
        let lastUsed: Date
    }

    /// The items to delete, in order, so the total is at or under `limit`.
    /// Empty when the cache already fits.
    static func victims(_ items: [Item], limit: Int64) -> [Item] {
        var total = items.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return [] }
        let order = items.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .preview }
            return lhs.lastUsed < rhs.lastUsed
        }
        var out: [Item] = []
        for item in order {
            out.append(item)
            total -= item.size
            if total <= limit { break }
        }
        return out
    }
}
