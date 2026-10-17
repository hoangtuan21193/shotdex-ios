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

/// Order of the group list (FS-06.06 §7.3).
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

/// Why the suggested keeper was suggested — the chips on it. Measured
/// reasons come first; with nothing measured, the file reason is named for
/// what it is ("Biggest file"), never "best" (§1).
enum DuplicateKeepReason: Hashable, Sendable {
    case eyesOpen, sharpest, edited, raw, favorite, live, biggestFile

    var title: String {
        switch self {
        case .eyesOpen: String(localized: "Eyes open", comment: "Duplicates: reason chip — the kept photo has eyes open where another has them closed")
        case .sharpest: String(localized: "Sharpest", comment: "Duplicates: reason chip — the kept photo is the sharpest of the group")
        case .edited: String(localized: "Edited", comment: "Duplicates: reason chip under the suggested keeper")
        case .raw: String(localized: "RAW", comment: "Duplicates: reason chip under the suggested keeper")
        case .favorite: String(localized: "Favorite", comment: "Duplicates: reason chip under the suggested keeper")
        case .live: String(localized: "Live", comment: "Duplicates: reason chip under the suggested keeper")
        case .biggestFile: String(localized: "Biggest file", comment: "Duplicates: reason chip — the kept photo is the biggest file, nothing was measured")
        }
    }
}

/// Pure rules behind the v2 decision card: which member to suggest keeping,
/// why, how each copy differs from it, and the card's geometry. No PhotoKit,
/// no UI — the screen feeds it hash rows plus traits.
enum DuplicateReview {

    /// The member the card suggests keeping. When **every** member is scored
    /// (§6): no closed eyes, then sharper, then less clipping; whatever the
    /// scores leave tied, and every group not fully scored, goes by the file
    /// rule D3 — the **edited** one, then the **favourite**, then the **bigger
    /// file**, then **more pixels**. Ties keep the grouper's order.
    static func keeper(
        of members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore] = [:]
    ) -> HashedPhoto? {
        guard var best = members.first else { return nil }
        let scored = isScored(members, scores)
        for member in members.dropFirst() {
            if scored, let verdict = DuplicateQuality.better(scores[member.assetId]!, than: scores[best.assetId]!) {
                if verdict { best = member }
            } else if ranks(member, above: best, traits: traits) {
                best = member
            }
        }
        return best
    }

    /// Every member has a measured score.
    static func isScored(_ members: [HashedPhoto], _ scores: [String: DuplicateQualityScore]) -> Bool {
        !members.isEmpty && members.allSatisfy { scores[$0.assetId]?.isScored == true }
    }

    /// The file rule D3: edited, then favourite, then bigger file, then more
    /// pixels. One rule for the keeper on the card and the order the grouper
    /// hands members over in (plan §8.1).
    static func ranks(
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
        scores: [String: DuplicateQualityScore] = [:],
        limit: Int = 2
    ) -> [DuplicateKeepReason] {
        let others = members.filter { $0.assetId != keeper.assetId }
        guard !others.isEmpty else { return [] }
        let mine = traits[keeper.assetId] ?? DuplicateMemberTraits()
        func trait(_ member: HashedPhoto) -> DuplicateMemberTraits {
            traits[member.assetId] ?? DuplicateMemberTraits()
        }
        var reasons: [DuplicateKeepReason] = []
        if isScored(members, scores), let kept = scores[keeper.assetId] {
            if kept.hasTrustedEyes, !kept.hasEyesClosed, others.contains(where: { scores[$0.assetId]?.hasEyesClosed == true }) {
                reasons.append(.eyesOpen)
            }
            let sharpness = kept.sharpness ?? 0
            if sharpness > 0, others.allSatisfy({ (scores[$0.assetId]?.sharpness ?? 0) < sharpness }),
               others.contains(where: { (scores[$0.assetId]?.sharpness ?? 0) < sharpness * DuplicateQuality.sharpnessTieRatio }) {
                reasons.append(.sharpest)
            }
        }
        if mine.isEdited, others.contains(where: { !trait($0).isEdited }) { reasons.append(.edited) }
        if mine.hasRAW, others.contains(where: { !trait($0).hasRAW }) { reasons.append(.raw) }
        if mine.isFavorite || keeper.isFavorite,
           others.contains(where: { !trait($0).isFavorite && !$0.isFavorite }) {
            reasons.append(.favorite)
        }
        if mine.isLive, others.contains(where: { !trait($0).isLive }) { reasons.append(.live) }
        // "Biggest file" only when nothing was measured: a sharpest keeper
        // that also happens to be the biggest file is kept for its sharpness.
        let size = keeper.fileSize ?? 0
        if !reasons.contains(.sharpest), !reasons.contains(.eyesOpen),
           size > 0, others.allSatisfy({ ($0.fileSize ?? 0) < size }) {
            reasons.append(.biggestFile)
        }
        return Array(reasons.prefix(limit))
    }

    /// One line under a copy saying what it lacks next to the keeper — the
    /// thing a thumbnail cannot show. Falls back to the copy's dimensions.
    static func difference(
        of copy: HashedPhoto,
        from keeper: HashedPhoto,
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore] = [:],
        groupSharpest: Double? = nil
    ) -> String {
        if let measured = qualityCaption(of: copy, keeper: keeper, scores: scores, groupSharpest: groupSharpest) {
            return measured
        }
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

    /// What the scores say is wrong with `copy`: *Eyes closed*, *Soft*,
    /// *Blown highlights*, *Too dark* — in that order (§6).
    static func qualityCaption(
        of copy: HashedPhoto,
        keeper: HashedPhoto,
        scores: [String: DuplicateQualityScore],
        groupSharpest: Double?
    ) -> String? {
        guard let mine = scores[copy.assetId], mine.isScored else { return nil }
        let kept = scores[keeper.assetId]
        if mine.hasEyesClosed {
            return String(localized: "Eyes closed", comment: "Duplicates: caption — someone in this photo has their eyes closed")
        }
        if let best = groupSharpest ?? kept?.sharpness, let sharpness = mine.sharpness,
           best > 0, sharpness <= best * DuplicateQuality.softRatio {
            return String(localized: "Soft", comment: "Duplicates: caption — this photo is noticeably less sharp than the sharpest")
        }
        if let kept, mine.highlightClip > DuplicateQuality.clipCaption, kept.highlightClip <= DuplicateQuality.clipKeeperMax {
            return String(localized: "Blown highlights", comment: "Duplicates: caption — bright parts of this photo are clipped to white")
        }
        if let kept, mine.shadowClip > DuplicateQuality.clipCaption, kept.shadowClip <= DuplicateQuality.clipKeeperMax {
            return String(localized: "Too dark", comment: "Duplicates: caption — dark parts of this photo are crushed to black")
        }
        return nil
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

/// Geometry of the decision card (FS-06.06 §7, board `PH_DuplicatesLargeGroup`):
/// one grid of `copyColumns + 2` square cells, 4pt apart. The keeper spans
/// 2×2 cells — each side twice a copy — at the top left; the copies fill the
/// cells to its right, then the rows below it, left to right, always square.
/// A big group fills the card instead of leaving the keeper alone in a column.
struct DuplicateCardMetrics: Equatable {
    static let copyGap: CGFloat = 4
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
        let cells = columns + 2
        let usable = innerWidth - Self.copyGap * CGFloat(cells - 1)
        let tile = max(24, (usable / CGFloat(cells)).rounded(.down))
        self.tile = tile
        self.keeper = tile * 2 + Self.copyGap
        self.copyColumns = columns
    }

    /// Cells across the card's grid: the keeper's two plus the copy columns.
    var gridColumns: Int { copyColumns + 2 }

    /// Top-left corner of each copy, in order, relative to the keeper's.
    /// Beside the keeper first (`copyColumns` wide, two rows), then full rows
    /// under it.
    func copyOrigins(count: Int) -> [CGPoint] {
        let step = tile + Self.copyGap
        let besideCount = min(count, copyColumns * 2)
        var origins: [CGPoint] = []
        origins.reserveCapacity(count)
        for index in 0..<besideCount {
            origins.append(CGPoint(
                x: keeper + Self.copyGap + CGFloat(index % copyColumns) * step,
                y: CGFloat(index / copyColumns) * step
            ))
        }
        for index in besideCount..<max(besideCount, count) {
            let below = index - besideCount
            origins.append(CGPoint(
                x: CGFloat(below % gridColumns) * step,
                y: keeper + Self.copyGap + CGFloat(below / gridColumns) * step
            ))
        }
        return origins
    }

    /// Height of the keeper and its copies together.
    func gridHeight(copyCount: Int) -> CGFloat {
        let below = max(0, copyCount - copyColumns * 2)
        let rows = (below + gridColumns - 1) / gridColumns
        return keeper + CGFloat(rows) * (tile + Self.copyGap)
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
