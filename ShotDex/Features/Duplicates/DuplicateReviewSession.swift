import Foundation
import Observation
import os

/// The user's work on the Duplicates screen (FS-06.06b §1): marks, keeper
/// picks, Keep all, folded groups and Not duplicates. Kept on disk in
/// `duplicate_review`, so it survives Back, other tabs, the background **and
/// the app being killed** — until the user deletes or undoes it.
///
/// The screen reads the in-memory copy, which changes at once; every change
/// is written to the store **in order on a background queue**, so a tap
/// never waits for the database writer the indexer is busy with. Owned by
/// `AppDependencies`, not by the screen's model, because the model is
/// rebuilt every time the screen opens.
@MainActor
@Observable
final class DuplicateReviewSession {
    private(set) var state: DuplicateReviewState
    @ObservationIgnored private let store: DuplicateReviewStore?
    @ObservationIgnored private let writes = DispatchQueue(label: "duplicates.review.writes", qos: .userInitiated)
    nonisolated private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "duplicates")

    /// Reads the table once at launch: a few hundred rows, one indexed read.
    init(store: DuplicateReviewStore?) {
        self.store = store
        do {
            self.state = try store?.load() ?? DuplicateReviewState()
        } catch {
            Self.log.error("Duplicates review read failed: \(error.localizedDescription, privacy: .public)")
            self.state = DuplicateReviewState()
        }
    }

    /// Waits for every queued write — for tests, and before a kill would matter.
    func flushWrites() {
        writes.sync {}
    }

    /// Runs a store write after every earlier one. A failure is logged —
    /// the screen keeps what the user did; it is the next launch that would
    /// miss it.
    private func persist(_ work: @escaping @Sendable (DuplicateReviewStore) throws -> Void) {
        guard let store else { return }
        writes.async {
            do { try work(store) } catch {
                Self.log.error("Duplicates review write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var marks: Set<String> { state.marks }

    func isMarked(_ assetId: String) -> Bool { state.marks.contains(assetId) }

    func setMarked(_ assetIds: some Collection<String>, _ marked: Bool) {
        let ids = Set(assetIds)
        let changed = marked ? ids.subtracting(state.marks) : ids.intersection(state.marks)
        guard !changed.isEmpty else { return }
        if marked { state.marks.formUnion(changed) } else { state.marks.subtract(changed) }
        persist { try $0.setMarked(changed, marked) }
    }

    /// Replaces the marks of `members` with exactly `marked`, as one write.
    func setMarks(of members: some Collection<String>, to marked: Set<String>) {
        let all = Set(members)
        let wanted = marked.intersection(all)
        guard state.marks.intersection(all) != wanted else { return }
        state.marks.subtract(all)
        state.marks.formUnion(wanted)
        persist { try $0.replaceMarks(of: all, with: wanted) }
    }

    // MARK: Keeper

    func keeper(among members: [String]) -> String? { state.keeper(among: members) }

    func setKeeper(_ keeper: String, groupMembers: [String]) {
        guard state.keeper(among: groupMembers) != keeper else { return }
        state.keepers.subtract(groupMembers)
        state.keepers.insert(keeper)
        persist { try $0.setKeeper(keeper, groupMembers: groupMembers) }
    }

    // MARK: Sets

    func isKeptAll(_ members: Set<String>) -> Bool { state.isKeptAll(members) }
    func isCollapsed(_ members: Set<String>) -> Bool { state.isCollapsed(members) }

    func setKeptAll(_ members: Set<String>, _ on: Bool) { setSet(.keepAll, members, on) }
    func setCollapsed(_ members: Set<String>, _ on: Bool) { setSet(.collapsed, members, on) }

    func dismissal(of members: Set<String>) -> DuplicateReviewState.Dismissal? { state.dismissal(of: members) }
    var notDuplicates: [DuplicateReviewSet] { state.notDuplicates }

    /// Not duplicates: the group leaves the list and every count (§9).
    func dismiss(_ members: Set<String>) {
        // A resurfaced group's old set is replaced by one holding the newcomer.
        dropSets(.notDuplicates, containingAnyOf: members)
        setSet(.notDuplicates, members, true)
    }

    /// Show again, from ⋯ ▸ Ignored.
    func undismiss(setId: String) {
        state.notDuplicates.removeAll { $0.id == setId }
        persist { try $0.removeSet(.notDuplicates, id: setId) }
    }

    // MARK: Cleanup

    /// Photos PhotoKit reported deleted: every row of theirs goes.
    func forget(_ assetIds: some Collection<String>) {
        let ids = Set(assetIds)
        guard !ids.isEmpty else { return }
        state.marks.subtract(ids)
        state.keepers.subtract(ids)
        for keyPath in [\DuplicateReviewState.keptAll, \.collapsed, \.notDuplicates] {
            state[keyPath: keyPath] = state[keyPath: keyPath].compactMap { set in
                var set = set
                set.members.subtract(ids)
                return set.members.isEmpty ? nil : set
            }
        }
        persist { try $0.forget(assetIds: ids) }
    }

    // MARK: Private

    private func setSet(_ role: DuplicateReviewRole, _ members: Set<String>, _ on: Bool) {
        guard !members.isEmpty else { return }
        if on {
            guard !contains(role, members) else { return }
            // The id is minted here so memory and disk agree on it.
            let id = UUID().uuidString
            append(role, DuplicateReviewSet(id: id, members: members, createdAt: Date()))
            persist { try $0.addSet(role, members: members, id: id) }
        } else {
            dropSets(role, containingAnyOf: members)
        }
    }

    private func contains(_ role: DuplicateReviewRole, _ members: Set<String>) -> Bool {
        switch role {
        case .keepAll: state.isKeptAll(members)
        case .collapsed: state.isCollapsed(members)
        case .notDuplicates: state.notDuplicates.contains { members.isSubset(of: $0.members) }
        case .mark, .keeper: false
        }
    }

    private func append(_ role: DuplicateReviewRole, _ set: DuplicateReviewSet) {
        switch role {
        case .keepAll: state.keptAll.append(set)
        case .collapsed: state.collapsed.append(set)
        case .notDuplicates: state.notDuplicates.append(set)
        case .mark, .keeper: break
        }
    }

    private func dropSets(_ role: DuplicateReviewRole, containingAnyOf members: Set<String>) {
        let keep: (DuplicateReviewSet) -> Bool = { $0.members.isDisjoint(with: members) }
        switch role {
        case .keepAll: state.keptAll = state.keptAll.filter(keep)
        case .collapsed: state.collapsed = state.collapsed.filter(keep)
        case .notDuplicates: state.notDuplicates = state.notDuplicates.filter(keep)
        case .mark, .keeper: return
        }
        persist { try $0.removeSets(role, containingAnyOf: members) }
    }
}
