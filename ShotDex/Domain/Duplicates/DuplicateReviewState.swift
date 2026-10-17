import Foundation

/// What `duplicate_review` holds, read back in one go (FS-06.06 §10,
/// FS-06.06b §1).
///
/// Marks and keeper picks are per photo — a photo is in one group only, so a
/// keeper id names its group. Keep all, folding and Not duplicates are per
/// *set of photos* rather than per group id: a regroup (Check Again) mints
/// new group ids, and the user's word has to outlive it.
struct DuplicateReviewState: Equatable, Sendable {
    var marks: Set<String> = []
    /// Photos the user picked to keep in their group (Keep this / Keep just
    /// this one). Overrides the suggestion.
    var keepers: Set<String> = []
    var keptAll: [DuplicateReviewSet] = []
    var collapsed: [DuplicateReviewSet] = []
    var notDuplicates: [DuplicateReviewSet] = []

    /// How a group stands against the user's Not duplicates sets (§9).
    enum Dismissal: Equatable, Sendable {
        /// Every member was in a set the user dismissed: the group is hidden.
        case hidden(setId: String)
        /// At least two members were dismissed together and a new photo joined
        /// since: the group shows again, with a line saying why.
        case newPhotoSince(setId: String)
    }

    func dismissal(of members: Set<String>) -> Dismissal? {
        var resurfaced: Dismissal?
        for set in notDuplicates {
            if members.isSubset(of: set.members) { return .hidden(setId: set.id) }
            if resurfaced == nil, members.intersection(set.members).count >= 2 {
                resurfaced = .newPhotoSince(setId: set.id)
            }
        }
        return resurfaced
    }

    func isKeptAll(_ members: Set<String>) -> Bool {
        keptAll.contains { members.isSubset(of: $0.members) }
    }

    func isCollapsed(_ members: Set<String>) -> Bool {
        collapsed.contains { members.isSubset(of: $0.members) }
    }

    /// The member the user picked to keep, if any.
    func keeper(among members: [String]) -> String? {
        members.first { keepers.contains($0) }
    }
}

/// A set of photos the user said something about as a whole.
struct DuplicateReviewSet: Equatable, Sendable, Identifiable {
    var id: String
    var members: Set<String>
    var createdAt: Date
}

enum DuplicateReviewRole: String, CaseIterable, Sendable {
    case mark, keeper, keepAll, collapsed, notDuplicates

    /// Roles stored once per photo rather than as a set.
    var isPerPhoto: Bool { self == .mark || self == .keeper }
}
