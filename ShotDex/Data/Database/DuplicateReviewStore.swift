import Foundation
import GRDB

/// Reads and writes `duplicate_review` — the user's work on the Duplicates
/// screen, kept until they delete or undo it (FS-06.06b §1). User data: the
/// indexer never touches this table and a regroup never clears it.
struct DuplicateReviewStore: Sendable {
    let database: AppDatabase

    // MARK: Reads

    /// Everything in one read. Rows with a role this build does not know are
    /// skipped, not fatal — one odd row must not take every mark with it.
    func load() throws -> DuplicateReviewState {
        try database.reader.read { db in
            var state = DuplicateReviewState()
            var sets: [DuplicateReviewRole: [String: (members: Set<String>, createdAt: Int)]] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT role, setId, assetId, createdAt FROM duplicate_review")
            while let row = try rows.next() {
                guard let role = DuplicateReviewRole(rawValue: row["role"]) else { continue }
                let assetId: String = row["assetId"]
                switch role {
                case .mark: state.marks.insert(assetId)
                case .keeper: state.keepers.insert(assetId)
                case .keepAll, .collapsed, .notDuplicates:
                    let setId: String = row["setId"]
                    let createdAt: Int = row["createdAt"]
                    sets[role, default: [:]][setId, default: ([], createdAt)].members.insert(assetId)
                }
            }
            func list(_ role: DuplicateReviewRole) -> [DuplicateReviewSet] {
                (sets[role] ?? [:])
                    .map { DuplicateReviewSet(id: $0.key, members: $0.value.members,
                                              createdAt: Date(timeIntervalSince1970: TimeInterval($0.value.createdAt))) }
                    .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            }
            state.keptAll = list(.keepAll)
            state.collapsed = list(.collapsed)
            state.notDuplicates = list(.notDuplicates)
            return state
        }
    }

    // MARK: Per-photo roles

    func setMarked(_ assetIds: some Collection<String>, _ marked: Bool, at date: Date = Date()) throws {
        try setPerPhoto(.mark, assetIds, marked, at: date)
    }

    /// Makes `keeper` the kept photo of its group: any other member's keeper
    /// pick goes, so a group never has two.
    func setKeeper(_ keeper: String, groupMembers: some Collection<String>, at date: Date = Date()) throws {
        let others = groupMembers.filter { $0 != keeper }
        try database.writer.write { db in
            try deletePerPhoto(db, .keeper, others)
            try insertPerPhoto(db, .keeper, [keeper], at: date)
        }
    }

    func clearKeeper(groupMembers: some Collection<String>) throws {
        try database.writer.write { db in try deletePerPhoto(db, .keeper, Array(groupMembers)) }
    }

    // MARK: Set roles

    /// Records `members` under `role` as one set and returns its id.
    @discardableResult
    func addSet(_ role: DuplicateReviewRole, members: some Collection<String>, at date: Date = Date()) throws -> String {
        precondition(!role.isPerPhoto, "\(role) is stored per photo")
        let setId = UUID().uuidString
        let stamp = Int(date.timeIntervalSince1970)
        try database.writer.write { db in
            for assetId in Set(members) {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO duplicate_review (role, setId, assetId, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [role.rawValue, setId, assetId, stamp]
                )
            }
        }
        return setId
    }

    func removeSet(_ role: DuplicateReviewRole, id setId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM duplicate_review WHERE role = ? AND setId = ?",
                           arguments: [role.rawValue, setId])
        }
    }

    /// Drops every set of `role` that holds any of `members` — undoing Keep
    /// all or unfolding a group whose id changed since.
    func removeSets(_ role: DuplicateReviewRole, containingAnyOf members: some Collection<String>) throws {
        let ids = Array(Set(members))
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            for chunk in ids.chunked(500) {
                try db.execute(
                    sql: """
                        DELETE FROM duplicate_review WHERE role = ? AND setId IN (
                            SELECT setId FROM duplicate_review WHERE role = ? AND assetId IN (\(databaseQuestionMarks(count: chunk.count))))
                        """,
                    arguments: StatementArguments([role.rawValue, role.rawValue]) + StatementArguments(chunk)
                )
            }
        }
    }

    // MARK: Cleanup

    /// Forgets photos that were deleted — here or in Photos. Every role: a
    /// mark on a gone photo must never be counted or deleted again.
    func forget(assetIds: some Collection<String>) throws {
        let ids = Array(Set(assetIds))
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            for chunk in ids.chunked(500) {
                try db.execute(
                    sql: "DELETE FROM duplicate_review WHERE assetId IN (\(databaseQuestionMarks(count: chunk.count)))",
                    arguments: StatementArguments(chunk)
                )
            }
        }
    }

    /// Rows for photos that left the library (their `photo_metadata` row is
    /// gone). Runs first in every scan. Returns how many went.
    @discardableResult
    func pruneOrphans() throws -> Int {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM duplicate_review WHERE assetId NOT IN (SELECT assetId FROM photo_metadata)")
            return db.changesCount
        }
    }

    // MARK: Private

    private func setPerPhoto(_ role: DuplicateReviewRole, _ assetIds: some Collection<String>, _ on: Bool, at date: Date) throws {
        let ids = Array(Set(assetIds))
        guard !ids.isEmpty else { return }
        try database.writer.write { db in
            if on { try insertPerPhoto(db, role, ids, at: date) } else { try deletePerPhoto(db, role, ids) }
        }
    }

    private func insertPerPhoto(_ db: Database, _ role: DuplicateReviewRole, _ ids: [String], at date: Date) throws {
        let stamp = Int(date.timeIntervalSince1970)
        for assetId in ids {
            try db.execute(
                sql: "INSERT OR IGNORE INTO duplicate_review (role, setId, assetId, createdAt) VALUES (?, '', ?, ?)",
                arguments: [role.rawValue, assetId, stamp]
            )
        }
    }

    private func deletePerPhoto(_ db: Database, _ role: DuplicateReviewRole, _ ids: [String]) throws {
        for chunk in ids.chunked(500) {
            try db.execute(
                sql: "DELETE FROM duplicate_review WHERE role = ? AND setId = '' AND assetId IN (\(databaseQuestionMarks(count: chunk.count)))",
                arguments: StatementArguments([role.rawValue]) + StatementArguments(chunk)
            )
        }
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
