import Foundation

/// What a group's kept photo takes from the copies deleted beside it
/// (FS-06.06b §2, replacing v2's Merge): their albums, the favorite, and —
/// read off the assets at write time — a location and, for copies of the
/// same moment only, the earliest capture date.
struct DuplicateInheritance: Equatable, Sendable {
    var keeperId: String
    /// Albums the user made that held a deleted copy and not the keeper.
    var albumIds: [String]
    /// A deleted copy was a favorite and the keeper is not.
    var favorite: Bool
    /// The deleted copies, oldest first, to take a location from.
    var donorIds: [String]
    /// Copies and smaller copies are one moment: the earliest date wins.
    /// A look-alike or a frame of a run keeps its own date.
    var takesEarliestDate: Bool

    var isEmpty: Bool { albumIds.isEmpty && !favorite && donorIds.isEmpty }

    /// Plans for every group losing photos in this delete. A group left with
    /// two or more unmarked photos has no single keeper — the user is keeping
    /// several frames — and inherits nothing.
    static func plan(
        groups: [DuplicateGroup],
        deleting: Set<String>,
        traits: [String: DuplicateMemberTraits]
    ) -> [DuplicateInheritance] {
        groups.compactMap { group in
            let gone = group.members.filter { deleting.contains($0.assetId) }
            let kept = group.members.filter { !deleting.contains($0.assetId) }
            guard !gone.isEmpty, kept.count == 1, let keeper = kept.first else { return nil }
            let keeperTraits = traits[keeper.assetId] ?? DuplicateMemberTraits(isFavorite: keeper.isFavorite)
            var albumIds: [String] = []
            for member in gone {
                for id in traits[member.assetId]?.albumIds ?? [] where !keeperTraits.albumIds.contains(id) && !albumIds.contains(id) {
                    albumIds.append(id)
                }
            }
            let favorite = !(keeperTraits.isFavorite || keeper.isFavorite)
                && gone.contains { traits[$0.assetId]?.isFavorite == true || $0.isFavorite }
            let plan = DuplicateInheritance(
                keeperId: keeper.assetId,
                albumIds: albumIds,
                favorite: favorite,
                donorIds: gone.sorted(by: DuplicateGrouper.oldestFirst).map(\.assetId),
                takesEarliestDate: group.kind.isCopy
            )
            return plan
        }
    }
}
