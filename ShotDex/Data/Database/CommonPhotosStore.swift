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
    /// A group is as new as its newest run's last change — an undo just
    /// done keeps the run it undid, and a day of Keep gathering stays as new
    /// as its last pass (FS-19.08 §6c) — then by insertion, so runs started
    /// in the same second still fall in one order.
    private static func keptRoots(_ db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, undoOf, state FROM common_photo_runs ORDER BY updatedAt DESC, createdAt DESC, rowid DESC
            """)
        let over: Set<String> = [CommonPhotosRun.State.stopped.rawValue, CommonPhotosRun.State.finished.rawValue]
        let runs = rows.map { (id: $0["id"] as String, root: ($0["undoOf"] as String?) ?? ($0["id"] as String),
                               isRoot: ($0["undoOf"] as String?) == nil, isOver: over.contains($0["state"] as String? ?? "")) }
        let unfinished = Set(runs.filter { !$0.isOver }.map(\.root))
        // Rows come newest first, so a root's first appearance is its
        // group's newest run.
        var seen: Set<String> = []
        let byNewest = runs.compactMap { run in seen.insert(run.root).inserted ? run.root : nil }
        let rootIds = Set(runs.filter(\.isRoot).map(\.id))
        let overRoots = byNewest.filter { rootIds.contains($0) && !unfinished.contains($0) }
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

    /// What earlier runs of a set gathered (FS-19.08 §6c): every source
    /// file of a photo they copied, moved or found already there, and when
    /// the newest of them ended. Undone photos are not counted: they are
    /// back as they were. Runs being finished (`finishing`) count — every
    /// photo of them is done. Only runs Activity still keeps are known.
    struct Gathered: Equatable, Sendable {
        var seen: Set<CommonPhotosIncremental.Stamp> = []
        /// Photos gathered and still there, each once — a photo Scan
        /// Everything found already there again is a second row, not a
        /// second photo.
        var photoCount: Int { photos.count }
        var photos: Set<String> = []
        var lastAt: Int?
        /// What the set's runs put in the destination and is still there at
        /// its size, by lowercased file name (§6d: the plan knows those bytes
        /// without reading them).
        var placed: [String: Placed] = [:]
        var isEmpty: Bool { lastAt == nil }
    }

    struct Placed: Equatable, Sendable {
        let size: Int64
        let sha256: String
    }

    /// `inDestination`, the sizes the destination holds now under each
    /// lowercased name: a gathered photo whose copy there is gone or another
    /// size is not counted, so it is gathered again (§6c). Nil: not checked.
    func gathered(connectionId: String, folders: [String], destination: String,
                  inDestination: [String: Set<Int64>]? = nil) throws -> Gathered {
        let key = CommonPhotosIncremental.setKey(connectionId: connectionId, folders: folders, destination: destination)
        return try database.reader.read { db in
            let runs = try CommonPhotosRun
                .filter(Column("connectionId") == connectionId && Column("undoOf") == nil)
                .filter([CommonPhotosRun.State.stopped, .finished, .finishing].map(\.rawValue).contains(Column("state")))
                .fetchAll(db)
                .filter { $0.isReadable && CommonPhotosIncremental.setKey(connectionId: $0.connectionId, folders: $0.folders,
                                                                          destination: $0.destination) == key }
            var out = Gathered()
            let decoder = JSONDecoder()
            // A photo Keep gathering put there and the user undid stays
            // undone: gathering it again 15 minutes later would undo the undo.
            let done = [CommonPhotosItem.Status.copied, .moved, .skipped].map(\.rawValue)
                + [CommonPhotosItem.Status.undone.rawValue]
            for run in runs {
                // The sources column only: a set's runs can hold many photos.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT sources, size, destinationPath, sha256, status FROM common_photo_items
                    WHERE runId = ? AND status IN (\(databaseQuestionMarks(count: done.count)))
                    """, arguments: StatementArguments([run.id] + done))
                guard !rows.isEmpty else { continue }
                for row in rows {
                    let undone = (row["status"] as String?) == CommonPhotosItem.Status.undone.rawValue
                    // Undone in a run from the sheet: offered again, as before.
                    if undone, run.watchId == nil { continue }
                    if let inDestination, !undone {
                        // Placed where, and is it still there at its size?
                        guard let placed: String = row["destinationPath"], let size: Int64 = row["size"],
                              inDestination[ServerUploadPath.lastComponent(of: placed).lowercased()]?.contains(size) == true
                        else { continue }
                    }
                    // Seen, not gathered: not in "N already gathered".
                    if !undone, let sha: String = row["sha256"] {
                        out.photos.insert(sha)
                        if let placed: String = row["destinationPath"], let size: Int64 = row["size"] {
                            out.placed[ServerUploadPath.lastComponent(of: placed).lowercased()] = Placed(size: size, sha256: sha)
                        }
                    }
                    let list: String = row["sources"]
                    guard let sources = try? decoder.decode([CommonPhotosItem.Source].self, from: Data(list.utf8)) else { continue }
                    for source in sources {
                        out.seen.insert(.init(path: source.path, size: source.size, modifiedAt: source.modifiedAt))
                    }
                }
                out.lastAt = max(out.lastAt ?? 0, run.updatedAt)
            }
            return out
        }
    }

    /// Runs a quit or a lost connection left half done, newest first — the
    /// Resume · Discard banner (FS-19.08 §7).
    func unfinishedRuns() throws -> [CommonPhotosRun] {
        try database.reader.read { db in
            try CommonPhotosRun
                // Not "in running, paused": a state this build cannot read is
                // listed too, so it can be discarded. A run ready to move waits
                // for the user, not for Resume.
                .filter(![CommonPhotosRun.State.stopped, .finished, .ready].map(\.rawValue).contains(Column("state")))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// An undo row written, and the row it undoes brought in line — in one
    /// write, so a quit never leaves one without the other: each copy the
    /// undo put back is no longer removed there, and an undone row is
    /// `undone` there too.
    func finishUndo(_ item: CommonPhotosItem, originalRunId: String, now: Int = Int(Date().timeIntervalSince1970)) throws {
        var item = item
        item.updatedAt = now
        do {
            try database.writer.write { db in
                try item.update(db)
                guard var original = try CommonPhotosItem.fetchOne(db, key: ["runId": originalRunId, "position": item.position]) else { return }
                let restored = Set(item.sources.filter { !$0.isRemoved }.map(\.path))
                for index in original.sources.indices where restored.contains(original.sources[index].path) {
                    original.sources[index].isRemoved = false
                }
                if item.status == .undone { original.status = .undone }
                original.updatedAt = now
                try original.update(db)
            }
        } catch is RecordError {
            throw RunMissing(runId: item.runId)
        }
    }

    /// Marks rows of `runId` undone (an undo's rows found done on resume).
    func markUndone(runId: String, positions: [Int], now: Int = Int(Date().timeIntervalSince1970)) throws {
        guard !positions.isEmpty else { return }
        try database.writer.write { db in
            for position in positions {
                try db.execute(sql: """
                    UPDATE common_photo_items SET status = ?, updatedAt = ? WHERE runId = ? AND position = ?
                    """, arguments: [CommonPhotosItem.Status.undone.rawValue, now, runId, position])
            }
        }
    }

    /// The runs' CSVs were removed from the server: forget their paths.
    func forgetCSVs(runIds: [String]) throws {
        guard !runIds.isEmpty else { return }
        try database.writer.write { db in
            for id in runIds {
                try db.execute(sql: "UPDATE common_photo_runs SET csvPath = NULL WHERE id = ?", arguments: [id])
            }
        }
    }

    /// Whether any row of `runId` can be undone (`CommonPhotosItem.isUndoable`),
    /// without reading every row: Copied, Moved, or a failed Move that
    /// removed a copy.
    func hasUndoableRows(runId: String) throws -> Bool {
        try database.reader.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM common_photo_items WHERE runId = ? AND (status IN ('copied', 'moved')
                    OR (status = 'failed' AND destinationPath IS NOT NULL AND sources LIKE '%"isRemoved":true%')))
                """, arguments: [runId]) ?? false
        }
    }

    /// The undo runs of `runId`, oldest first.
    func undoRuns(of runId: String) throws -> [CommonPhotosRun] {
        try database.reader.read { db in
            try CommonPhotosRun.filter(Column("undoOf") == runId).order(Column("createdAt"), Column.rowID).fetchAll(db)
        }
    }

    // MARK: History moves (FS-19.08 §6b)

    /// Records the history rows a Move's finish rewrote, inside that write.
    static func recordHistoryMoves(_ db: Database, runId: String, rows: [ServerFileHistory.MovedRow]) throws {
        for row in rows {
            try db.execute(sql: """
                INSERT INTO common_photo_history_moves (runId, historyTable, rowId, sourcePath, pathBefore, pathAfter)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [runId, row.table, row.rowId, row.sourcePath, row.pathBefore, row.pathAfter])
        }
    }

    /// The history rows `runId` moved, with the record ids.
    func historyMoves(runId: String) throws -> [(id: Int64, row: ServerFileHistory.MovedRow)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, historyTable, rowId, sourcePath, pathBefore, pathAfter FROM common_photo_history_moves
                WHERE runId = ? ORDER BY id
                """, arguments: [runId]).map { row in
                (row["id"], ServerFileHistory.MovedRow(table: row["historyTable"], rowId: row["rowId"], pathBefore: row["pathBefore"],
                                                       pathAfter: row["pathAfter"], sourcePath: row["sourcePath"]))
            }
        }
    }

    /// Puts back the history rows `runId` moved away from `restored` — the
    /// copies an undo wrote back — then forgets those records. Safe to run
    /// again after a quit between the two: a row is put back only while it
    /// still holds the path the move gave it.
    func restoreHistory(runId: String, restored: Set<String>, history: ServerFileHistory) throws {
        let moves = try historyMoves(runId: runId).filter { restored.contains($0.row.sourcePath) }
        guard !moves.isEmpty else { return }
        let settled = try history.restore(moves.map(\.row))
        try database.writer.write { db in
            for (move, isSettled) in zip(moves, settled) where isSettled {
                try db.execute(sql: "DELETE FROM common_photo_history_moves WHERE id = ?", arguments: [move.id])
            }
        }
    }

    /// Discard, and Remove from List: the run and its log go — with its undo
    /// runs — and nothing on the server changes.
    func discard(runId: String) throws {
        _ = try database.writer.write { db in try CommonPhotosRun.deleteOne(db, key: runId) }
    }
}

// MARK: - Keep gathering's day runs (FS-19.08 §6c)

extension CommonPhotosStore {
    /// `yyyy-MM-dd` in the Mac's time zone: the day a pass gathers for.
    static func day(of date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Runs Keep gathering found for a Move set, waiting for the user
    /// (FS-19.08 §6c), newest first.
    func readyRuns() throws -> [CommonPhotosRun] {
        try database.reader.read { db in
            try CommonPhotosRun.filter(Column("state") == CommonPhotosRun.State.ready.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Move N… said yes: a ready run becomes a run to resume. False when it
    /// was not ready any more (moved, discarded), or — `asOf`, the
    /// `updatedAt` the user's list was read at — a pass changed the list
    /// since: nothing changes then, and the user is asked again.
    func confirmReady(runId: String, asOf: Int? = nil, now: Int = Int(Date().timeIntervalSince1970)) throws -> Bool {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE common_photo_runs SET state = ?, updatedAt = ?
                WHERE id = ? AND state = ? AND (? IS NULL OR updatedAt = ?)
                """, arguments: [CommonPhotosRun.State.running.rawValue, now, runId, CommonPhotosRun.State.ready.rawValue, asOf, asOf])
            return db.changesCount > 0
        }
    }

    /// Not Now for good (Remove from List, Stop Gathering, the connection
    /// deleted): the photos a ready run lists go — nothing was moved. Rows
    /// it already moved on an earlier confirm stay, and their run is
    /// finished again.
    func dropReady(runId: String) throws {
        try database.writer.write { db in try Self.dropReady(runId: runId, in: db) }
    }

    /// A Move set's pass found nothing: whatever its ready run listed went
    /// (moved by hand, deleted), so the list goes too.
    func dropReady(watchId: String) throws {
        try database.writer.write { db in
            for runId in try String.fetchAll(db, sql: "SELECT id FROM common_photo_runs WHERE watchId = ? AND state = ?",
                                             arguments: [watchId, CommonPhotosRun.State.ready.rawValue]) {
                try Self.dropReady(runId: runId, in: db)
            }
        }
    }

    static func dropReady(runId: String, in db: Database) throws {
        guard try String.fetchOne(db, sql: "SELECT state FROM common_photo_runs WHERE id = ?", arguments: [runId])
            == CommonPhotosRun.State.ready.rawValue else { return }
        try db.execute(sql: "DELETE FROM common_photo_items WHERE runId = ? AND status = ?",
                       arguments: [runId, CommonPhotosItem.Status.pending.rawValue])
        let left = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM common_photo_items WHERE runId = ?", arguments: [runId]) ?? 0
        if left == 0 {
            try db.execute(sql: "DELETE FROM common_photo_runs WHERE id = ?", arguments: [runId])
        } else {
            try db.execute(sql: "UPDATE common_photo_runs SET state = ? WHERE id = ?",
                           arguments: [CommonPhotosRun.State.finished.rawValue, runId])
        }
    }

    /// The day's run is still going or being undone: nothing added.
    struct DayRunBusy: Error, Equatable { let runId: String }

    /// What a pass put into a run: which run, and how many of its photos
    /// were not there before — a Move set's notice says so only then.
    struct DayGathered: Equatable { let runId: String; let added: Int }

    /// Puts what a pass found into the set's run of the day — a new one for
    /// the day's first pass, or after the user stopped the day's run — and
    /// returns its id, ready to run. Positions follow the ones already
    /// there. Throws `DayRunBusy` while that run still goes.
    ///
    /// `ready` (a Move set): a run of its own that waits for the user. A run
    /// already waiting takes this pass's list in place of its own — the
    /// photos it listed are found again, unless they went — so the set
    /// never has two.
    func gatherIntoDay(_ run: CommonPhotosRun, items: [CommonPhotosItem], watchId: String, day: String, ready: Bool = false,
                       now: Int = Int(Date().timeIntervalSince1970)) throws -> DayGathered {
        precondition(!items.isEmpty, "a day's run gains photos, never an empty pass")
        let state: CommonPhotosRun.State = ready ? .ready : .running
        func firstPath(_ item: CommonPhotosItem) -> String? { item.sources.first?.path }
        return try database.writer.write { db in
            if ready, let waiting = try CommonPhotosRun
                .filter(Column("watchId") == watchId && Column("undoOf") == nil && Column("state") == CommonPhotosRun.State.ready.rawValue)
                .filter(Column("action") == run.action.rawValue)
                .order(Column("createdAt").desc)
                .fetchOne(db) {
                let old = try CommonPhotosItem.filter(Column("runId") == waiting.id).fetchAll(db)
                let listed = Set(old.filter { $0.status == .pending }.compactMap(firstPath))
                try db.execute(sql: "DELETE FROM common_photo_items WHERE runId = ? AND status = ?",
                               arguments: [waiting.id, CommonPhotosItem.Status.pending.rawValue])
                let kept = old.filter { $0.status != .pending }
                let next = (kept.map(\.position).max() ?? -1) + 1
                for (offset, item) in items.enumerated() {
                    var item = item
                    item.runId = waiting.id
                    item.position = next + offset
                    try item.insert(db)
                }
                // Nothing moved in it yet: it is today's list now. `updatedAt`
                // moves on every change, even within a second — Move N…
                // confirms against it.
                try db.execute(sql: "UPDATE common_photo_runs SET day = ?, updatedAt = ? WHERE id = ?",
                               arguments: [kept.isEmpty ? day : waiting.day, max(now, waiting.updatedAt + 1), waiting.id])
                return DayGathered(runId: waiting.id, added: items.filter { !listed.contains(firstPath($0) ?? "") }.count)
            }
            // The set's own action only: a set switched from Move to Copy
            // never adds to — and runs — a Move of the same day.
            let today = try CommonPhotosRun
                .filter(Column("watchId") == watchId && Column("day") == day && Column("undoOf") == nil)
                .filter(Column("action") == run.action.rawValue)
                .order(Column("createdAt").desc)
                .fetchOne(db)
            if let today {
                // Still going (running, paused, finishing) or being undone:
                // this pass adds nothing — the next one will find the photos.
                let undoing = try Bool.fetchOne(db, sql: """
                    SELECT EXISTS (SELECT 1 FROM common_photo_runs WHERE undoOf = ? AND state NOT IN ('finished', 'stopped'))
                    """, arguments: [today.id]) ?? false
                if today.isUnfinished || undoing { throw DayRunBusy(runId: today.id) }
            }
            // An earlier day's run still to go on holds these photos too:
            // they wait for it, never in a second run (§6c).
            if let earlier = try String.fetchOne(db, sql: """
                SELECT id FROM common_photo_runs WHERE watchId = ? AND undoOf IS NULL AND state IN ('running', 'paused', 'finishing')
                ORDER BY createdAt DESC LIMIT 1
                """, arguments: [watchId]) {
                throw DayRunBusy(runId: earlier)
            }
            // A day the user stopped gets a run of its own for what follows.
            // So does a Move set's list: the day's moved photos stay a
            // finished run, kept and undoable, while the new ones wait.
            if !ready, let open = today, open.state == .finished {
                let next = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM common_photo_items WHERE runId = ?",
                                             arguments: [open.id]) ?? -1) + 1
                for (offset, item) in items.enumerated() {
                    var item = item
                    item.runId = open.id
                    item.position = next + offset
                    try item.insert(db)
                }
                try db.execute(sql: "UPDATE common_photo_runs SET state = ?, updatedAt = ? WHERE id = ?",
                               arguments: [state.rawValue, now, open.id])
                return DayGathered(runId: open.id, added: items.count)
            }
            var run = run
            run.watchId = watchId
            run.day = day
            run.state = state
            try run.insert(db)
            for item in items {
                var item = item
                item.runId = run.id
                try item.insert(db)
            }
            return DayGathered(runId: run.id, added: items.count)
        }
    }
}
