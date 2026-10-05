import CoreGraphics
import Foundation

/// What the Duplicates card needs to know about one member beyond its hash
/// row: facts PhotoKit only gives per asset (favourite, Live) or per resource
/// list (edited, RAW). Read once per card, off the main thread, never from the
/// network (FS-06.06 §7).
struct DuplicateMemberTraits: Hashable, Sendable {
    var isEdited = false
    var hasRAW = false
    var isLive = false
    var isFavorite = false
}

/// Order of the group list (FS-06.06 §7, v2 header "Most space first ▾").
enum DuplicateSort: String, CaseIterable, Identifiable, Sendable {
    case mostSpace
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostSpace: String(localized: "Most space first", comment: "Duplicates sort order: groups that free the most space first")
        case .newest: String(localized: "Newest first", comment: "Duplicates sort order")
        case .oldest: String(localized: "Oldest first", comment: "Duplicates sort order")
        }
    }
}

/// Why the suggested keeper was suggested — the chips under it on the card.
enum DuplicateKeepReason: Hashable, Sendable {
    case edited, raw, favorite, live, largest

    var title: String {
        switch self {
        case .edited: String(localized: "Edited", comment: "Duplicates: reason chip under the suggested keeper")
        case .raw: String(localized: "RAW", comment: "Duplicates: reason chip under the suggested keeper")
        case .favorite: String(localized: "Favorite", comment: "Duplicates: reason chip under the suggested keeper")
        case .live: String(localized: "Live", comment: "Duplicates: reason chip under the suggested keeper")
        case .largest: String(localized: "Largest", comment: "Duplicates: reason chip under the suggested keeper")
        }
    }
}

/// Pure rules behind the v2 decision card: which member to suggest keeping,
/// why, how each copy differs from it, and the card's geometry. No PhotoKit,
/// no UI — the screen feeds it hash rows plus traits.
enum DuplicateReview {

    /// The member the card suggests keeping (D3): the **edited** one, then the
    /// **favourite**, then the **bigger file**, then **more pixels**. An edit
    /// or a heart is work the user did; file size and pixels are proxies for
    /// "least re-compressed". Ties keep the grouper's order.
    static func keeper(
        of members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits]
    ) -> HashedPhoto? {
        guard var best = members.first else { return nil }
        for member in members.dropFirst() where ranks(member, above: best, traits: traits) {
            best = member
        }
        return best
    }

    private static func ranks(
        _ left: HashedPhoto,
        above right: HashedPhoto,
        traits: [String: DuplicateMemberTraits]
    ) -> Bool {
        let leftTraits = traits[left.assetId] ?? DuplicateMemberTraits(isFavorite: left.isFavorite)
        let rightTraits = traits[right.assetId] ?? DuplicateMemberTraits(isFavorite: right.isFavorite)
        if leftTraits.isEdited != rightTraits.isEdited { return leftTraits.isEdited }
        let leftFavorite = leftTraits.isFavorite || left.isFavorite
        let rightFavorite = rightTraits.isFavorite || right.isFavorite
        if leftFavorite != rightFavorite { return leftFavorite }
        let leftSize = left.fileSize ?? 0, rightSize = right.fileSize ?? 0
        if leftSize != rightSize { return leftSize > rightSize }
        return left.pixelCount > right.pixelCount
    }

    /// Chips under the keeper, most telling first, at most `limit`. A reason
    /// is only shown when it sets the keeper apart from at least one copy —
    /// "Edited" on a keeper whose copies are all edited explains nothing.
    static func reasons(
        keeper: HashedPhoto,
        members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits],
        limit: Int = 2
    ) -> [DuplicateKeepReason] {
        let others = members.filter { $0.assetId != keeper.assetId }
        guard !others.isEmpty else { return [] }
        let mine = traits[keeper.assetId] ?? DuplicateMemberTraits()
        func trait(_ member: HashedPhoto) -> DuplicateMemberTraits {
            traits[member.assetId] ?? DuplicateMemberTraits()
        }
        var reasons: [DuplicateKeepReason] = []
        if mine.isEdited, others.contains(where: { !trait($0).isEdited }) { reasons.append(.edited) }
        if mine.hasRAW, others.contains(where: { !trait($0).hasRAW }) { reasons.append(.raw) }
        if mine.isFavorite || keeper.isFavorite,
           others.contains(where: { !trait($0).isFavorite && !$0.isFavorite }) {
            reasons.append(.favorite)
        }
        if mine.isLive, others.contains(where: { !trait($0).isLive }) { reasons.append(.live) }
        let size = keeper.fileSize ?? 0
        if size > 0, others.allSatisfy({ ($0.fileSize ?? 0) < size }) { reasons.append(.largest) }
        return Array(reasons.prefix(limit))
    }

    /// One line under a copy saying what it lacks next to the keeper — the
    /// thing a thumbnail cannot show. Falls back to the copy's dimensions.
    static func difference(
        of copy: HashedPhoto,
        from keeper: HashedPhoto,
        traits: [String: DuplicateMemberTraits]
    ) -> String {
        let mine = traits[copy.assetId] ?? DuplicateMemberTraits(isFavorite: copy.isFavorite)
        let kept = traits[keeper.assetId] ?? DuplicateMemberTraits(isFavorite: keeper.isFavorite)
        if kept.isEdited, !mine.isEdited {
            return String(localized: "Not edited", comment: "Duplicates: a copy lacks the keeper's edit")
        }
        if kept.hasRAW, !mine.hasRAW {
            return String(localized: "JPEG only", comment: "Duplicates: a copy has no RAW file, unlike the keeper")
        }
        if kept.isFavorite || keeper.isFavorite, !(mine.isFavorite || copy.isFavorite) {
            return String(localized: "Not favorite", comment: "Duplicates: a copy is not a favorite, unlike the keeper")
        }
        if kept.isLive, !mine.isLive {
            return String(localized: "Still photo", comment: "Duplicates: a copy is not a Live Photo, unlike the keeper")
        }
        return dimensions(copy) ?? "—"
    }

    static func dimensions(_ photo: HashedPhoto) -> String? {
        guard let width = photo.width, let height = photo.height else { return nil }
        return "\(width)×\(height)"
    }

    /// Bytes freed if every member but `keeper` goes.
    static func freeBytes(members: [HashedPhoto], keeper: HashedPhoto) -> Int {
        members.reduce(0) { $0 + ($1.assetId == keeper.assetId ? 0 : ($1.fileSize ?? 0)) }
    }

    /// "4 s apart", "3 min apart", "2 h apart" — first to last capture. `nil`
    /// when fewer than two members carry a date, or all share one second.
    static func spanText(_ members: [HashedPhoto]) -> String? {
        let dates = members.compactMap(\.creationDate)
        guard dates.count >= 2, let first = dates.min(), let last = dates.max() else { return nil }
        let seconds = last - first
        switch seconds {
        case ..<1:
            return nil
        case ..<60:
            return String(localized: "\(seconds) s apart", comment: "Duplicates: seconds between the first and last photo of a group")
        case ..<3600:
            return String(localized: "\(seconds / 60) min apart", comment: "Duplicates: minutes between the first and last photo of a group")
        case ..<86_400:
            return String(localized: "\(seconds / 3600) h apart", comment: "Duplicates: hours between the first and last photo of a group")
        default:
            return String(localized: "\(seconds / 86_400) days apart", comment: "Duplicates: days between the first and last photo of a group")
        }
    }

    /// Newest capture in the group, as the sort and the header date use it.
    static func newestDate(_ group: DuplicateGroup) -> Int {
        group.members.compactMap(\.creationDate).max() ?? 0
    }

    static func sorted(
        _ groups: [DuplicateGroup],
        by sort: DuplicateSort,
        freeBytes: (DuplicateGroup) -> Int
    ) -> [DuplicateGroup] {
        switch sort {
        case .mostSpace:
            let keyed = groups.map { ($0, freeBytes($0)) }
            return keyed.enumerated().sorted { left, right in
                if left.element.1 != right.element.1 { return left.element.1 > right.element.1 }
                return left.offset < right.offset
            }.map(\.element.0)
        case .newest:
            return groups.enumerated().sorted { left, right in
                let a = newestDate(left.element), b = newestDate(right.element)
                return a != b ? a > b : left.offset < right.offset
            }.map(\.element)
        case .oldest:
            return groups.enumerated().sorted { left, right in
                let a = newestDate(left.element), b = newestDate(right.element)
                return a != b ? a < b : left.offset < right.offset
            }.map(\.element)
        }
    }
}

/// Geometry of the decision card (FS-06.06 §7): the keeper spans two copy
/// tiles plus one gap, the copies fill `copyColumns` columns beside it.
/// Spacing is on the DESIGN.md scale — 4 between copies, 8 between the keeper
/// and the copies.
struct DuplicateCardMetrics: Equatable {
    static let copyGap: CGFloat = 4
    static let keeperGap: CGFloat = 8
    static let cardPadding: CGFloat = 12
    static let compactColumns = 2
    static let regularColumns = 3
    static let columnRange = 1...5
    /// Regular width lays cards out in columns of at least this width (Z2).
    static let minimumCardWidth: CGFloat = 400
    static let cardSpacing: CGFloat = 16

    let tile: CGFloat
    let keeper: CGFloat
    let copyColumns: Int

    /// - Parameters:
    ///   - innerWidth: card width minus its two paddings.
    ///   - copyColumns: copies per row, the density the user pinched to.
    init(innerWidth: CGFloat, copyColumns: Int) {
        let columns = max(1, copyColumns)
        let usable = innerWidth - Self.keeperGap - Self.copyGap * CGFloat(columns - 1)
        let tile = max(24, (usable / CGFloat(columns + 2)).rounded(.down))
        self.tile = tile
        self.keeper = tile * 2 + Self.copyGap
        self.copyColumns = columns
    }

    /// Card columns for a content width: one on compact, as many ≥ 400pt
    /// columns as fit on regular.
    static func cardColumns(contentWidth: CGFloat, isRegular: Bool) -> Int {
        guard isRegular else { return 1 }
        return max(1, Int((contentWidth + cardSpacing) / (minimumCardWidth + cardSpacing)))
    }

    static func cardWidth(contentWidth: CGFloat, columns: Int) -> CGFloat {
        (contentWidth - cardSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
}
