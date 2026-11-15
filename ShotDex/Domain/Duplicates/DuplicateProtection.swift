import Foundation

/// Why a photo is never marked for the user (FS-06.06 §1, A2): it is a
/// favorite, it carries an edit, or it is in an album the user made. A
/// shortcut (Remove the other N, Quick clean) skips it; the user can still
/// tap its ring.
enum DuplicateProtection: Hashable, Sendable {
    case favorite
    case edited
    case album(String)

    static func of(_ photo: HashedPhoto, traits: [String: DuplicateMemberTraits]) -> DuplicateProtection? {
        let mine = traits[photo.assetId] ?? DuplicateMemberTraits()
        if mine.isFavorite || photo.isFavorite { return .favorite }
        if mine.isEdited || photo.isExportOfEdit { return .edited }
        if let album = mine.albums.first { return .album(album) }
        return nil
    }

    /// "favorite", "edited", "in album" — or "in album Client" when named.
    func text(namingAlbum: Bool) -> String {
        switch self {
        case .favorite: String(localized: "favorite", comment: "Duplicates: why a photo was kept — it is a favorite")
        case .edited: String(localized: "edited", comment: "Duplicates: why a photo was kept — it has an edit")
        case .album(let name):
            namingAlbum
                ? String(localized: "in album \(name)", comment: "Duplicates: why a photo was kept — it is in the named album")
                : String(localized: "in album", comment: "Duplicates: why a photo was kept — it is in an album the user made")
        }
    }

    /// "2 kept: favorite, in album" under a card; "1 kept: in album Mai & Huy"
    /// on a Quick clean row. `nil` when nothing was kept.
    static func keptLine(_ kept: [DuplicateProtection], namingAlbums: Bool) -> String? {
        guard !kept.isEmpty else { return nil }
        var seen: [String] = []
        for reason in kept {
            let text = reason.text(namingAlbum: namingAlbums)
            if !seen.contains(text) { seen.append(text) }
        }
        return String(localized: "\(kept.count) kept: \(seen.joined(separator: ", "))",
                      comment: "Duplicates: how many photos a shortcut left unmarked, and why")
    }
}

/// What a shortcut would mark in one group: every member but the keeper,
/// minus protected photos.
struct DuplicateRemoval: Equatable, Sendable {
    var remove: [String]
    var kept: [DuplicateProtection]
    var removeBytes: Int

    static func plan(
        members: [HashedPhoto],
        keeper: HashedPhoto,
        traits: [String: DuplicateMemberTraits]
    ) -> DuplicateRemoval {
        var remove: [String] = [], kept: [DuplicateProtection] = [], bytes = 0
        for member in members where member.assetId != keeper.assetId {
            if let reason = DuplicateProtection.of(member, traits: traits) {
                kept.append(reason)
            } else {
                remove.append(member.assetId)
                bytes += member.fileSize ?? 0
            }
        }
        return DuplicateRemoval(remove: remove, kept: kept, removeBytes: bytes)
    }
}

/// One row of the Quick clean sheet (§7.2): a copies group, what it keeps
/// and what it would mark.
struct QuickCleanItem: Identifiable, Equatable, Sendable {
    var id: String { groupId }
    var groupId: String
    var keeperId: String
    var removal: DuplicateRemoval
}

enum QuickClean {
    /// Copies and smaller copies — the same picture, so nothing is lost —
    /// that would mark at least one photo. Brackets never (§5).
    static func items(
        groups: [DuplicateGroup],
        keeper: (DuplicateGroup) -> HashedPhoto?,
        traits: [String: DuplicateMemberTraits]
    ) -> [QuickCleanItem] {
        groups.compactMap { group in
            guard group.kind.isCopy, group.sourceSet == nil, let kept = keeper(group) else { return nil }
            let removal = DuplicateRemoval.plan(members: group.members, keeper: kept, traits: traits)
            guard !removal.remove.isEmpty else { return nil }
            return QuickCleanItem(groupId: group.id, keeperId: kept.assetId, removal: removal)
        }
    }

    /// Photos to mark for the ticked rows.
    static func selection(_ items: [QuickCleanItem], excluding unticked: Set<String>) -> [String] {
        items.filter { !unticked.contains($0.groupId) }.flatMap(\.removal.remove)
    }
}

/// Suggested picks (FS-06.06 §14.5, after Immich's "Deduplicate all"): the
/// Quick clean of look-alikes — only groups whose keeper is **clearly**
/// better, so a shortcut never decides a coin flip.
enum SuggestedPicks {
    /// Whether `keeper` is clearly the one to keep: measured, it beats every
    /// other copy outright on the scoring rule the keeper is picked by (eyes,
    /// then sharpness past the tie ratio, then clipping — no tie); not
    /// measured, it beats every other on the file rule's first three steps:
    /// edited, favourite, a file more than 1% bigger. Photo info and pixel
    /// count alone are ties here.
    static func isClear(
        _ group: DuplicateGroup,
        keeper: HashedPhoto,
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore]
    ) -> Bool {
        if DuplicateReview.isScored(group.members, scores), let mine = scores[keeper.assetId] {
            return group.members.allSatisfy { other in
                other.assetId == keeper.assetId
                    || scores[other.assetId].map { DuplicateQuality.better(mine, than: $0) == true } == true
            }
        }
        func tier(_ photo: HashedPhoto) -> (edited: Bool, favorite: Bool) {
            let trait = traits[photo.assetId] ?? DuplicateMemberTraits()
            return (trait.isEdited || photo.isExportOfEdit, trait.isFavorite || photo.isFavorite)
        }
        let mine = tier(keeper), size = keeper.fileSize ?? 0
        return group.members.allSatisfy { other in
            guard other.assetId != keeper.assetId else { return true }
            let theirs = tier(other)
            if mine.edited != theirs.edited { return mine.edited }
            if mine.favorite != theirs.favorite { return mine.favorite }
            let otherSize = other.fileSize ?? 0
            return size > otherSize && !DuplicateReview.sizesTie(size, otherSize)
        }
    }

    /// Look-alike groups (not bursts, not brackets) with a clear keeper that
    /// would mark at least one photo — protected photos (A2) never marked.
    static func items(
        groups: [DuplicateGroup],
        keeper: (DuplicateGroup) -> HashedPhoto?,
        traits: [String: DuplicateMemberTraits],
        scores: [String: DuplicateQualityScore]
    ) -> [QuickCleanItem] {
        groups.compactMap { group in
            guard group.kind == .similar, group.sourceSet == nil, let kept = keeper(group),
                  isClear(group, keeper: kept, traits: traits, scores: scores) else { return nil }
            let removal = DuplicateRemoval.plan(members: group.members, keeper: kept, traits: traits)
            guard !removal.remove.isEmpty else { return nil }
            return QuickCleanItem(groupId: group.id, keeperId: kept.assetId, removal: removal)
        }
    }
}
