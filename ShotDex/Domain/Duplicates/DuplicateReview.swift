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
    case eyesOpen, sharpest, edited, raw, favorite, live, biggestFile, moreInfo

    var title: String {
        switch self {
        case .eyesOpen: String(localized: "Eyes open", comment: "Duplicates: reason chip — the kept photo has eyes open where another has them closed")
        case .sharpest: String(localized: "Sharpest", comment: "Duplicates: reason chip — the kept photo is the sharpest of the group")
        case .edited: String(localized: "Edited", comment: "Duplicates: reason chip under the suggested keeper")
        case .raw: String(localized: "RAW", comment: "Duplicates: reason chip under the suggested keeper")
        case .favorite: String(localized: "Favorite", comment: "Duplicates: reason chip under the suggested keeper")
        case .live: String(localized: "Live", comment: "Duplicates: reason chip under the suggested keeper")
        case .biggestFile: String(localized: "Biggest file", comment: "Duplicates: reason chip — the kept photo is the biggest file, nothing was measured")
        case .moreInfo: String(localized: "More photo info", comment: "Duplicates: reason chip — the copies are the same size and the kept one carries more camera, lens and location details")
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
    /// rule D3 (`fileOrder`): where quality has no verdict, the copy earlier
    /// in that order stays (so a 1% size band and photo info decide a quality
    /// tie too, §14.4).
    static func keeper(
        of members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore] = [:]
    ) -> HashedPhoto? {
        guard isScored(members, scores) else { return fileOrder(members, traits: traits).first }
        // Quality first, as a set (`DuplicateQuality.leaders`); the file
        // order breaks what quality leaves tied.
        return fileOrder(DuplicateQuality.leaders(of: members, scores: scores), traits: traits).first
    }

    /// The file rule D3 as an order, best first: the **edited** ones, then the
    /// **favourites**, then by **file size** — where sizes within 1% are one
    /// band, anchored on the band's largest file, and inside a band the copy
    /// with **more photo info** (§14.4), then **more pixels**, comes first.
    /// Anything still tied keeps its place in `members`.
    ///
    /// An order over the whole set, not a pairwise "above": a 1% band is not
    /// transitive (5.00 / 4.97 / 4.94 MB), so a comparator built on it would
    /// pick a different keeper for every order the members arrive in.
    static func fileOrder(
        _ members: [HashedPhoto],
        traits: [String: DuplicateMemberTraits]
    ) -> [HashedPhoto] {
        func tier(_ photo: HashedPhoto) -> (edited: Bool, favorite: Bool) {
            let trait = traits[photo.assetId] ?? DuplicateMemberTraits(isFavorite: photo.isFavorite)
            // An export from Lightroom & co. is an edit someone delivered (§7.4).
            return (trait.isEdited || photo.isExportOfEdit, trait.isFavorite || photo.isFavorite)
        }
        let indexed = members.enumerated().map { (index: $0.offset, photo: $0.element, tier: tier($0.element)) }
        let bySize = indexed.sorted { a, b in
            if a.tier.edited != b.tier.edited { return a.tier.edited }
            if a.tier.favorite != b.tier.favorite { return a.tier.favorite }
            let left = a.photo.fileSize ?? 0, right = b.photo.fileSize ?? 0
            return left != right ? left > right : a.index < b.index
        }
        var result: [HashedPhoto] = []
        var rest = bySize[...]
        while let anchor = rest.first {
            let band = rest.prefix {
                $0.tier == anchor.tier && sizesTie($0.photo.fileSize ?? 0, anchor.photo.fileSize ?? 0)
            }
            rest = rest.dropFirst(band.count)
            result += band.sorted { a, b in
                if a.photo.infoFieldCount != b.photo.infoFieldCount { return a.photo.infoFieldCount > b.photo.infoFieldCount }
                if a.photo.pixelCount != b.photo.pixelCount { return a.photo.pixelCount > b.photo.pixelCount }
                return a.index < b.index
            }.map(\.photo)
        }
        return result
    }

    /// Every member has a measured score.
    static func isScored(_ members: [HashedPhoto], _ scores: [String: DuplicateQualityScore]) -> Bool {
        !members.isEmpty && members.allSatisfy { scores[$0.assetId]?.isScored == true }
    }

    /// Two file sizes count as the same when they are within 1% of the larger
    /// (FS-06.06 §14.4) — a re-save or a stripped header moves a few bytes.
    static let sizeTieRatio = 0.01

    static func sizesTie(_ left: Int, _ right: Int) -> Bool {
        guard left != right else { return true }
        let larger = max(left, right)
        guard larger > 0 else { return true }
        return Double(abs(left - right)) <= Double(larger) * sizeTieRatio
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
        // A scored group was decided by its scores (or tied on them): the
        // file size did not decide, so no chip says it did.
        let measured = reasons.contains(.sharpest) || reasons.contains(.eyesOpen) || isScored(members, scores)
        if !measured, size > 0,
           others.allSatisfy({ ($0.fileSize ?? 0) < size && !sizesTie($0.fileSize ?? 0, size) }) {
            reasons.append(.biggestFile)
        } else if !isScored(members, scores), keeper.infoFieldCount > 0,
                  others.allSatisfy({ other in
                      // Info decided it only when the edited and favourite
                      // tiers did not, and every size is a tie (§14.4).
                      (trait(other).isEdited || other.isExportOfEdit) == (mine.isEdited || keeper.isExportOfEdit)
                          && (trait(other).isFavorite || other.isFavorite) == (mine.isFavorite || keeper.isFavorite)
                          && sizesTie(other.fileSize ?? 0, size)
                          && other.infoFieldCount < keeper.infoFieldCount
                  }) {
            reasons.append(.moreInfo)
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

/// Geometry of the decision card (FS-06.06 §7): one grid of square cells,
/// all the same size, 4pt apart, members in a fixed order left to right.
/// The kept photo carries a Keep badge, not a bigger cell (user,
/// 2026-11-10): a bigger keeper made the cells swap places whenever the
/// suggestion changed, so a tap landed on another photo than the one aimed at.
struct DuplicateCardMetrics: Equatable {
    static let copyGap: CGFloat = 4
    static let cardPadding: CGFloat = 12
    /// The stored density: photos per row minus one (kept from when it
    /// counted copies beside a 2×2 keeper, so a pinched density survives).
    static let compactColumns = 2
    static let regularColumns = 3
    static let columnRange = 1...5
    /// Regular width lays cards out in columns of at least this width (Z2).
    static let minimumCardWidth: CGFloat = 400
    static let cardSpacing: CGFloat = 16
    /// Between the group bar (All Keep / All Trash, Keep All) and the tiles.
    static let barGap: CGFloat = 10

    /// File name and size lines under a tile (Immich-style, user
    /// 2026-11-16) only when the tile is at least this big.
    static let infoMinimumTile: CGFloat = 110
    static let infoGap: CGFloat = 6
    static let infoHeight: CGFloat = 34
    static let infoRowGap: CGFloat = 8

    let tile: CGFloat
    let copyColumns: Int
    let innerWidth: CGFloat

    /// - Parameters:
    ///   - innerWidth: card width minus its two paddings.
    ///   - copyColumns: the density the user pinched to.
    init(innerWidth: CGFloat, copyColumns: Int) {
        let columns = max(1, copyColumns)
        let cells = columns + 1
        let usable = innerWidth - Self.copyGap * CGFloat(cells - 1)
        self.tile = max(24, (usable / CGFloat(cells)).rounded(.down))
        self.copyColumns = columns
        self.innerWidth = innerWidth
    }

    /// The layout for one group: never more photos per row than it has, so
    /// the common two-photo group fills the card with two big tiles
    /// (user, 2026-11-16: "most duplicates are two photos — make them bigger").
    func fitting(photoCount: Int) -> DuplicateCardMetrics {
        let columns = min(copyColumns, max(1, photoCount - 1))
        return columns == copyColumns ? self : DuplicateCardMetrics(innerWidth: innerWidth, copyColumns: columns)
    }

    /// Photos per row.
    var gridColumns: Int { copyColumns + 1 }

    /// Whether each tile carries its file name and size underneath.
    var showsInfo: Bool { tile >= Self.infoMinimumTile }

    /// Vertical distance from one row of tiles to the next.
    var rowStep: CGFloat {
        showsInfo ? tile + Self.infoGap + Self.infoHeight + Self.infoRowGap : tile + Self.copyGap
    }

    /// Top-left corner of the photo at `index`, left to right, row by row.
    func origin(at index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index % gridColumns) * (tile + Self.copyGap), y: CGFloat(index / gridColumns) * rowStep)
    }

    /// Height of a group's grid.
    func gridHeight(photoCount: Int) -> CGFloat {
        let rows = max(1, (photoCount + gridColumns - 1) / gridColumns)
        let last = showsInfo ? tile + Self.infoGap + Self.infoHeight : tile
        return CGFloat(rows - 1) * rowStep + last
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
