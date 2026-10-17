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
