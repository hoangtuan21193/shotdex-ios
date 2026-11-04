import Foundation
import GRDB

/// Reads and writes the original-on-device answers (FS-06.10 §5). A pass is
/// the rows themselves: it asks for items not looked at since it started,
/// so killing the app mid-way loses nothing (AC-6).
struct OriginalPresenceStore: Sendable {
    let database: AppDatabase

    /// The pass in progress, or the last one.
    struct Pass: Equatable, Sendable {
        var startedAt: Int64
        /// `nil` while it is still running.
        var finishedAt: Int64?
    }

    /// How far a pass has come, over the Photos items the app can see.
    struct Progress: Equatable, Sendable {
        /// Items looked at since the pass started.
        var checked = 0
        var total = 0
    }

    // MARK: Pass

    func pass() throws -> Pass? {
        try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT startedAt, finishedAt FROM original_presence_pass WHERE id = 1")
                .map { Pass(startedAt: $0["startedAt"], finishedAt: $0["finishedAt"]) }
        }
    }

    /// Starts a new pass at `now`: every row older than it is due again.
    func beginPass(at now: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO original_presence_pass (id, startedAt, finishedAt) VALUES (1, ?, NULL)",
                           arguments: [now])
        }
    }

    func finishPass(at now: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE original_presence_pass SET finishedAt = ? WHERE id = 1", arguments: [now])
        }
    }

    // MARK: Items

    /// The next items a pass started at `since` has not looked at: those
    /// marked for a recheck first, then those never checked, then the oldest.
    /// Only Photos items the grid shows: hidden and recently deleted ones
    /// cannot be read anyway. Three narrow queries on indexes rather than one
    /// sort of the whole library per batch — a pass over 55k runs ~275 of them.
    func nextBatch(since: Int64, limit: Int = 200) throws -> [String] {
        let visible = PhotoVisibility.condition
        let isVisiblePhoto = """
            EXISTS (SELECT 1 FROM photo_copies pc WHERE pc.photoKitId = o.photoKitId AND pc.kind = 'photos'
                    AND pc.photoId IN (SELECT assetId FROM photo_metadata WHERE \(visible)))
            """
        return try database.reader.read { db in
            var ids = try String.fetchAll(db, sql: """
                SELECT o.photoKitId FROM original_presence o
                WHERE o.checkedAt IS NULL AND \(isVisiblePhoto)
                ORDER BY o.photoKitId LIMIT ?
                """, arguments: [limit])
            if ids.count < limit {
                ids += try String.fetchAll(db, sql: """
                    SELECT pc.photoKitId FROM photo_copies pc
                    WHERE pc.kind = 'photos' AND pc.photoKitId IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM original_presence o WHERE o.photoKitId = pc.photoKitId)
                      AND pc.photoId IN (SELECT assetId FROM photo_metadata WHERE \(visible))
                    ORDER BY pc.photoKitId LIMIT ?
                    """, arguments: [limit - ids.count])
            }
            if ids.count < limit {
                ids += try String.fetchAll(db, sql: """
                    SELECT o.photoKitId FROM original_presence o
                    WHERE o.checkedAt < ? AND \(isVisiblePhoto)
                    ORDER BY o.checkedAt, o.photoKitId LIMIT ?
                    """, arguments: [since, limit - ids.count])
            }
            return ids
        }
    }

    /// Stores what one batch found. `nil` is "could not tell": the item is
    /// looked at (the pass moves on) but stays unchecked.
    func record(_ results: [String: OriginalPresence?], at now: Int64) throws {
        guard !results.isEmpty else { return }
        try database.writer.write { db in
            for (id, state) in results {
                try db.execute(sql: "INSERT OR REPLACE INTO original_presence (photoKitId, state, checkedAt) VALUES (?, ?, ?)",
                               arguments: [id, state?.rawValue, now])
            }
        }
    }

    /// Items PhotoKit says changed go back to unchecked (AC-8): they are in
    /// neither value until the check reaches them again, first in line.
    func markForRecheck(_ photoKitIds: some Collection<String>) throws {
        guard !photoKitIds.isEmpty else { return }
        try database.writer.write { db in
            for chunk in Array(photoKitIds).chunked(into: 500) {
                try db.execute(sql: """
                    UPDATE original_presence SET state = NULL, checkedAt = NULL
                    WHERE photoKitId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(chunk))
            }
        }
    }

    func state(of photoKitId: String) throws -> OriginalPresence? {
        try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT state FROM original_presence WHERE photoKitId = ?", arguments: [photoKitId])
                .flatMap(OriginalPresence.init(rawValue:))
        }
    }

    /// The line under a smart album: items the grid can show, and how many of
    /// them this pass has looked at (AC-9 — under `.limited` the index only
    /// holds the shared items, so the total is theirs).
    func progress(since: Int64) throws -> Progress {
        let visible = PhotoVisibility.condition
        return try database.reader.read { db in
            let photos = "SELECT photoKitId FROM photo_copies WHERE kind = 'photos' AND photoKitId IS NOT NULL AND photoId IN (SELECT assetId FROM photo_metadata WHERE \(visible))"
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT photoKitId) FROM (\(photos))") ?? 0
            let checked = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM original_presence WHERE checkedAt >= ? AND photoKitId IN (\(photos))
                """, arguments: [since]) ?? 0
            return Progress(checked: checked, total: total)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
