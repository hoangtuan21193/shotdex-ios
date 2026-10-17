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
    /// Albums the user made that hold this photo, by title.
    var albums: [String] = []
    /// The same albums' identifiers, for the kept photo to join them.
    var albumIds: [String] = []
}

/// Order of the group list (FS-06.06 §7.3).
enum DuplicateSort: String, CaseIterable, Identifiable, Sendable {
    /// The surest suggestions first: the widest score gap between the
    /// keeper and the next best (A7).
    case easiestFirst
    case mostSpace
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easiestFirst: String(localized: "Easiest first", comment: "Duplicates sort order: groups where the suggestion is surest first")
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
        // An export from Lightroom & co. is an edit someone delivered (§7.4).
        let leftEdited = leftTraits.isEdited || left.isExportOfEdit
        let rightEdited = rightTraits.isEdited || right.isExportOfEdit
        if leftEdited != rightEdited { return leftEdited }
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
        if mine.isEdited || keeper.isExportOfEdit,
           others.contains(where: { !trait($0).isEdited && !$0.isExportOfEdit }) { reasons.append(.edited) }
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

    /// The caption inside a copy (§7.4, D10): at most two lines of plain
    /// words — what it lacks next to the keeper, then where it came from or
    /// where it lives, then the shot settings that differ in the group. No
    /// pixel counts, no MB: those are for the viewer. Empty when there is
    /// nothing worth saying.
    static func caption(
        of copy: HashedPhoto,
        keeper: HashedPhoto,
        members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore] = [:]
    ) -> [String] {
        let sharpest = isScored(members, scores) ? members.compactMap { scores[$0.assetId]?.sharpness }.max() : nil
        let lines = [
            weakness(of: copy, keeper: keeper, traits: traits, scores: scores, groupSharpest: sharpest),
            origin(of: copy, keeper: keeper, traits: traits),
            settings(of: copy, members: members),
        ]
        return Array(lines.compactMap { $0 }.prefix(2))
    }

    /// Line 1: what this copy loses to the keeper, most telling first.
    static func weakness(
        of copy: HashedPhoto,
        keeper: HashedPhoto,
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore],
        groupSharpest: Double?
    ) -> String? {
        if let measured = qualityCaption(of: copy, keeper: keeper, scores: scores, groupSharpest: groupSharpest) {
            return measured
        }
        if let mine = copy.longEdge, let kept = keeper.longEdge,
           Double(mine) <= Double(kept) * DuplicateGrouper.smallerEdgeRatio {
            return String(localized: "Smaller copy", comment: "Duplicates: caption — this copy has fewer pixels than the kept photo")
        }
        let mine = traits[copy.assetId] ?? DuplicateMemberTraits(isFavorite: copy.isFavorite)
        let kept = traits[keeper.assetId] ?? DuplicateMemberTraits(isFavorite: keeper.isFavorite)
        if kept.isEdited || keeper.isExportOfEdit, !mine.isEdited, !copy.isExportOfEdit {
            return String(localized: "Not edited", comment: "Duplicates: a copy lacks the keeper's edit")
        }
        if kept.hasRAW, !mine.hasRAW {
            return String(localized: "JPEG only", comment: "Duplicates: a copy has no RAW file, unlike the keeper")
        }
        if kept.isLive, !mine.isLive {
            return String(localized: "Still photo", comment: "Duplicates: a copy is not a Live Photo, unlike the keeper")
        }
        return nil
    }

    /// Line 2: where the copy came from or where it lives.
    static func origin(of copy: HashedPhoto, keeper: HashedPhoto, traits: [String: DuplicateMemberTraits]) -> String? {
        if let messenger = messenger(of: copy) { return messenger }
        if copy.isExportOfEdit, let name = keeper.originalFilename.map(stem), !name.isEmpty {
            return String(localized: "Export of \(name)", comment: "Duplicates: caption — this copy is an export of the named original")
        }
        let mine = traits[copy.assetId] ?? DuplicateMemberTraits(isFavorite: copy.isFavorite)
        if let album = mine.albums.first {
            return String(localized: "In album: \(album)", comment: "Duplicates: caption — this copy is in one of the user's albums")
        }
        if mine.isFavorite || copy.isFavorite {
            return String(localized: "Favorite", comment: "Duplicates: caption — this copy is a favorite")
        }
        return nil
    }

    /// The messenger a re-saved copy came through, read off the file name
    /// the app gave it ("IMG-20260101-WA0007.jpg").
    static func messenger(of photo: HashedPhoto) -> String? {
        guard let name = photo.originalFilename?.uppercased() else { return nil }
        if name.contains("-WA") { return "WhatsApp" }
        if name.contains("ZALO") { return "Zalo" }
        if name.hasPrefix("TELEGRAM") || name.hasPrefix("PHOTO_") { return "Telegram" }
        if name.hasPrefix("RECEIVED_") || name.contains("MESSENGER") { return "Messenger" }
        return nil
    }

    /// Settings that differ inside the group, this copy's values: "−2 EV ·
    /// 35mm · 1/60 s". A setting all members share says nothing.
    static func settings(of copy: HashedPhoto, members: [HashedPhoto]) -> String? {
        var parts: [String] = []
        if let ev = copy.exposureBias, Set(members.map { $0.exposureBias.map { ($0 * 10).rounded() } }).count > 1 {
            parts.append("\(DuplicateSourceSet.signedEV(ev)) EV")
        }
        if let focal = copy.focalLength, Set(members.map { $0.focalLength.map { $0.rounded() } }).count > 1 {
            parts.append("\(Int(focal.rounded()))mm")
        }
        if let shutter = copy.shutterDisplay, Set(members.map(\.shutterDisplay)).count > 1 {
            parts.append(shutter.hasSuffix("s") ? "\(shutter.dropLast()) s" : shutter)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func stem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
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

    /// "within 4 seconds", "within 3 minutes", "within 2 hours", "3 days
    /// apart" — first to last capture (FS-06.06 §11). `nil`
    /// when fewer than two members carry a date, or all share one second.
    static func spanText(_ members: [HashedPhoto]) -> String? {
        let dates = members.compactMap(\.creationDate)
        guard dates.count >= 2, let first = dates.min(), let last = dates.max() else { return nil }
        let seconds = last - first
        switch seconds {
        case ..<1:
            return nil
        case ..<60:
            return String(localized: "within \(seconds) seconds", comment: "Duplicates: seconds between the first and last photo of a group")
        case ..<3600:
            return String(localized: "within \(seconds / 60 + (seconds % 60 > 0 ? 1 : 0)) minutes", comment: "Duplicates: minutes between the first and last photo of a group")
        case ..<86_400:
            return String(localized: "within \(seconds / 3600 + (seconds % 3600 > 0 ? 1 : 0)) hours", comment: "Duplicates: hours between the first and last photo of a group")
        default:
            return String(localized: "\(seconds / 86_400) days apart", comment: "Duplicates: days between the first and last photo of a group")
        }
    }

    /// Newest capture in the group, as the sort and the header date use it.
    static func newestDate(_ group: DuplicateGroup) -> Int {
        group.members.compactMap(\.creationDate).max() ?? 0
    }

    /// One number per scored photo, 0…1: open eyes weigh most, then
    /// sharpness relative to the group's sharpest, then little clipping.
    static func qualityValue(_ score: DuplicateQualityScore, groupSharpest: Double) -> Double {
        let eyes = score.hasEyesClosed ? 0.0 : 1.0
        let sharp = groupSharpest > 0 ? (score.sharpness ?? 0) / groupSharpest : 0
        let clip = 1 - min(1, (score.highlightClip + score.shadowClip) * 10)
        return eyes * 0.5 + sharp * 0.4 + clip * 0.1
    }

    /// How sure the suggestion is: the keeper's quality value minus the
    /// best other member's. Copies are as sure as it gets (1); a group not
    /// fully scored is not sure at all (0).
    static func scoreGap(
        _ group: DuplicateGroup,
        keeper: HashedPhoto,
        scores: [String: DuplicateQualityScore]
    ) -> Double {
        if group.kind.isCopy { return 1 }
        guard isScored(group.members, scores) else { return 0 }
        let sharpest = group.members.compactMap { scores[$0.assetId]?.sharpness }.max() ?? 0
        let kept = qualityValue(scores[keeper.assetId]!, groupSharpest: sharpest)
        let next = group.members.filter { $0.assetId != keeper.assetId }
            .map { qualityValue(scores[$0.assetId]!, groupSharpest: sharpest) }.max() ?? 0
        return max(0, kept - next)
    }

    static func sorted(
        _ groups: [DuplicateGroup],
        by sort: DuplicateSort,
        freeBytes: (DuplicateGroup) -> Int,
        scoreGap: (DuplicateGroup) -> Double = { _ in 0 }
    ) -> [DuplicateGroup] {
        switch sort {
        case .easiestFirst:
            let keyed = groups.map { ($0, scoreGap($0)) }
            return keyed.enumerated().sorted { left, right in
                if left.element.1 != right.element.1 { return left.element.1 > right.element.1 }
                return left.offset < right.offset
            }.map(\.element.0)
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
