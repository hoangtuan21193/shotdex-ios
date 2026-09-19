import Foundation
import GRDB
import Observation

/// Picks, rejects and star ratings — the culling pass that happens before any
/// editing.
///
/// A `*Store` because it reads and writes. Its own table, not columns on
/// `photo_metadata`: the indexer replaces whole metadata rows, so anything it
/// does not carry is lost on the next pass, and this is user-entered data.
///
/// A missing row means "untouched". Writing a state that is back to untouched
/// deletes the row rather than storing zeroes, so `SELECT COUNT(*)` on this
/// table answers "how much of this library has been culled".
@MainActor
@Observable
final class CullStore {
    /// Every culled photo, by asset id, held in memory.
    ///
    /// The whole table, not a window of it: a row exists only for a photo the
    /// user has flagged or rated, so even a heavily culled library of 50k
    /// photos is a few thousand entries of three fields. Grids read this
    /// rather than querying per tile — a badge that costs a database round
    /// trip per cell is a badge that drops frames while scrolling.
    private(set) var states: [String: PhotoCullState] = [:]
    /// Bumped on every write, so a view that cannot diff a dictionary cheaply
    /// (the UIKit grid) still knows when to re-render its tiles.
    private(set) var version = 0

    @ObservationIgnored private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
        reloadAll()
    }

    /// Reads the whole table into `states`. Called at launch and after the
    /// indexer's prune, which is the only writer other than this store.
    func reloadAll() {
        let rows = (try? database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT assetId, rating, flag FROM photo_cull")
        }) ?? []
        states = Dictionary(uniqueKeysWithValues: rows.map { row in
            let state = Self.state(from: row)
            return (state.assetId, state)
        })
        version &+= 1
    }

    func state(assetId: String) throws -> PhotoCullState {
        try database.reader.read { db in
            try Self.row(db, assetId: assetId) ?? PhotoCullState(assetId: assetId)
        }
    }

    /// Bulk read for a grid or a filmstrip: one query, not one per tile.
    func states(assetIds: [String]) throws -> [String: PhotoCullState] {
        guard !assetIds.isEmpty else { return [:] }
        return try database.reader.read { db in
            let placeholders = databaseQuestionMarks(count: assetIds.count)
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT assetId, rating, flag FROM photo_cull WHERE assetId IN (\(placeholders))",
                arguments: StatementArguments(assetIds)
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let state = Self.state(from: row)
                return (state.assetId, state)
            })
        }
    }

    func setRating(_ rating: Int, ids: [String]) throws {
        try update(ids: ids) { state in
            state.rating = PhotoCullState.clampedRating(rating)
        }
    }

    func setFlag(_ flag: PhotoFlag, ids: [String]) throws {
        try update(ids: ids) { state in
            state.flag = flag
        }
    }

    /// How many photos in the library carry a flag or a rating, for the
    /// Collections token.
    func culledCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_cull") ?? 0
        }
    }

    /// Drops rows for assets that are gone, called from the same sweep that
    /// prunes metadata.
    func deleteAssets(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        defer {
            for id in ids { states.removeValue(forKey: id) }
            version &+= 1
        }
        try database.writer.write { db in
            let placeholders = databaseQuestionMarks(count: ids.count)
            try db.execute(
                sql: "DELETE FROM photo_cull WHERE assetId IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    private func update(ids: [String], _ change: (inout PhotoCullState) -> Void) throws {
        guard !ids.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        var written: [String: PhotoCullState] = [:]
        // The cache is updated only after the write commits: a failed write
        // must not leave a badge on a photo the database does not agree about.
        defer { applyToCache(written) }
        try database.writer.write { db in
            for id in ids {
                var state = try Self.row(db, assetId: id) ?? PhotoCullState(assetId: id)
                change(&state)
                written[id] = state
                if state.isEmpty {
                    try db.execute(
                        sql: "DELETE FROM photo_cull WHERE assetId = ?",
                        arguments: [id]
                    )
                } else {
                    try db.execute(
                        sql: """
                            INSERT OR REPLACE INTO photo_cull
                                (assetId, rating, flag, updatedAt)
                            VALUES (?, ?, ?, ?)
                            """,
                        arguments: [id, state.rating, state.flag.rawValue, now]
                    )
                }
            }
        }
    }

    private func applyToCache(_ written: [String: PhotoCullState]) {
        guard !written.isEmpty else { return }
        for (id, state) in written {
            if state.isEmpty {
                states.removeValue(forKey: id)
            } else {
                states[id] = state
            }
        }
        version &+= 1
    }

    private static func row(_ db: Database, assetId: String) throws -> PhotoCullState? {
        try Row.fetchOne(
            db,
            sql: "SELECT assetId, rating, flag FROM photo_cull WHERE assetId = ?",
            arguments: [assetId]
        )
        .map(state(from:))
    }

    private static func state(from row: Row) -> PhotoCullState {
        PhotoCullState(
            assetId: row["assetId"],
            rating: row["rating"] ?? 0,
            flag: PhotoFlag(rawValue: row["flag"] ?? 0) ?? .unflagged
        )
    }
}

/// `?, ?, ?` for an `IN` list. GRDB has no helper that takes a count alone.
private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
}
