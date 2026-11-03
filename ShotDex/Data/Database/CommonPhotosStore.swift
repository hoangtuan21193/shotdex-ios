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

    /// A run that ends (finished or stopped) makes room: past
    /// `keptRunCount` finished runs, the oldest go with their log (§6b).
    func markState(_ state: CommonPhotosRun.State, runId: String, csvPath: String? = nil,
                  now: Int = Int(Date().timeIntervalSince1970)) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE common_photo_runs SET state = ?, updatedAt = ?, csvPath = COALESCE(?, csvPath) WHERE id = ?
                """, arguments: [state.rawValue, now, csvPath, runId])
            if db.changesCount == 0 { throw RunMissing(runId: runId) }
            if state == .finished || state == .stopped { try Self.prune(db) }
        }
    }

    /// How many finished runs Activity keeps, so they can still be undone
    /// (FS-19.08 §6b). A run and its undo runs count as one.
    static let keptRunCount = 20

    /// Every finished and stopped run — gathering runs and their undo
    /// runs — of the `keptRunCount` newest groups, newest first. A group
    /// counts once, so this can list more than `keptRunCount` runs.
    func keptRuns() throws -> [CommonPhotosRun] {
        try database.reader.read { db in
            let over = try CommonPhotosRun
                .filter([CommonPhotosRun.State.stopped, .finished].map(\.rawValue).contains(Column("state")))
                .order(Column("createdAt").desc, Column.rowID.desc)
                .fetchAll(db)
            let roots = try Self.keptRoots(db)
            return over.filter { roots.contains($0.undoOf ?? $0.id) }
        }
    }

    /// The gathering runs whose group is kept: the newest `keptRunCount`
    /// whose every run is over, plus every group with a run still going.
    /// Newest by creation, then by insertion — runs started in the same
    /// second still fall in one order.
    private static func keptRoots(_ db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, undoOf, state FROM common_photo_runs ORDER BY createdAt DESC, rowid DESC
            """)
        let over: Set<String> = [CommonPhotosRun.State.stopped.rawValue, CommonPhotosRun.State.finished.rawValue]
        let runs = rows.map { (id: $0["id"] as String, root: ($0["undoOf"] as String?) ?? ($0["id"] as String),
                               isRoot: ($0["undoOf"] as String?) == nil, isOver: over.contains($0["state"] as String? ?? "")) }
        let unfinished = Set(runs.filter { !$0.isOver }.map(\.root))
        let overRoots = runs.filter { $0.isRoot && !unfinished.contains($0.id) }.map(\.id)
        return unfinished.union(overRoots.prefix(keptRunCount))
    }

    /// Deletes the groups past the kept ones; their undo runs, photos and
    /// history records go with them (foreign keys cascade). The CSV each
    /// left in the destination stays: it is the user's lasting record.
    private static func prune(_ db: Database) throws {
        let kept = try keptRoots(db)
        let roots = try String.fetchAll(db, sql: "SELECT id FROM common_photo_runs WHERE undoOf IS NULL")
        for root in roots where !kept.contains(root) {
            _ = try CommonPhotosRun.deleteOne(db, key: root)
        }
    }

    enum UndoRefusal: Error, Equatable {
        /// The run is going, paused or finishing, or is itself an undo.
        case notOver
        /// An undo of it has not finished: resume or discard that first.
        case undoUnfinished
        /// None of the chosen photos is Copied or Moved.
        case nothingToUndo
    }

    /// Starts an undo of `runId` (FS-19.08 §6b): a run of its own over the
    /// chosen photos — every Copied or Moved one when `positions` is nil —
    /// each a copy of the run's row, waiting. Rows keep their position, so
    /// each names the row it undoes.
    @discardableResult
    func startUndo(of runId: String, positions: Set<Int>? = nil, id: String = UUID().uuidString,
                   now: Int = Int(Date().timeIntervalSince1970)) throws -> CommonPhotosRun {
        try database.writer.write { db in
            guard let original = try CommonPhotosRun.fetchOne(db, key: runId), original.undoOf == nil,
                  original.isOver, original.isReadable else { throw UndoRefusal.notOver }
            let undoes = try CommonPhotosRun.filter(Column("undoOf") == runId).fetchAll(db)
            guard undoes.allSatisfy(\.isOver) else { throw UndoRefusal.undoUnfinished }
            let items = try CommonPhotosItem.filter(Column("runId") == runId).order(Column("position")).fetchAll(db)
                .filter { $0.isUndoable && (positions?.contains($0.position) ?? true) }
            guard !items.isEmpty else { throw UndoRefusal.nothingToUndo }
            let undo = CommonPhotosRun(id: id, connectionId: original.connectionId, folders: original.folders,
                                       destination: original.destination, action: original.action, createdAt: now,
                                       undoOf: runId)
            try undo.insert(db)
            for item in items {
                var row = item
                row.runId = id
                row.status = .pending
                row.partPath = nil
                row.reason = nil
                row.updatedAt = now
                try row.insert(db)
            }
            return undo
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

    /// Discard, and Remove from List: the run and its log go — with its undo
    /// runs — and nothing on the server changes.
    func discard(runId: String) throws {
        _ = try database.writer.write { db in try CommonPhotosRun.deleteOne(db, key: runId) }
    }
}
