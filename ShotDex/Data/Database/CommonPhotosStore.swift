import Foundation
import GRDB

/// Reads and writes common-photos runs and their photos (FS-19.08 §8). The
/// runner writes an item before and after every server step, so a run
/// resumes from the database alone.
///
/// Discard deletes a run and its log: the caller stops the runner first.
/// A write to a run that is gone throws `RunMissing`, so a runner left going
/// finds out rather than writing into nothing.
struct CommonPhotosStore: Sendable {
    struct RunMissing: Error, Equatable {
        let runId: String
    }

    let database: AppDatabase

    func start(_ run: CommonPhotosRun, items: [CommonPhotosItem]) throws {
        try database.writer.write { db in
            try run.insert(db)
            for item in items { try item.insert(db) }
        }
    }

    func update(_ item: CommonPhotosItem, now: Int = Int(Date().timeIntervalSince1970)) throws {
        var item = item
        item.updatedAt = now
        do {
            try database.writer.write { db in try item.update(db) }
        } catch is RecordError {
            throw RunMissing(runId: item.runId)
        }
    }

    func markState(_ state: CommonPhotosRun.State, runId: String, csvPath: String? = nil,
                  now: Int = Int(Date().timeIntervalSince1970)) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE common_photo_runs SET state = ?, updatedAt = ?, csvPath = COALESCE(?, csvPath) WHERE id = ?
                """, arguments: [state.rawValue, now, csvPath, runId])
            if db.changesCount == 0 { throw RunMissing(runId: runId) }
        }
    }

    func run(id: String) throws -> CommonPhotosRun? {
        try database.reader.read { db in try CommonPhotosRun.fetchOne(db, key: id) }
    }

    func items(runId: String) throws -> [CommonPhotosItem] {
        try database.reader.read { db in
            try CommonPhotosItem.filter(Column("runId") == runId).order(Column("position")).fetchAll(db)
        }
    }

    /// Runs a quit or a lost connection left half done, newest first — the
    /// Resume · Discard banner (FS-19.08 §7).
    func unfinishedRuns() throws -> [CommonPhotosRun] {
        try database.reader.read { db in
            try CommonPhotosRun
                // Not "in running, paused": a state this build cannot read is
                // listed too, so it can be discarded.
                .filter(![CommonPhotosRun.State.stopped, .finished].map(\.rawValue).contains(Column("state")))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Discard: the run and its log go; nothing on the server changes.
    func discard(runId: String) throws {
        _ = try database.writer.write { db in try CommonPhotosRun.deleteOne(db, key: runId) }
    }
}
