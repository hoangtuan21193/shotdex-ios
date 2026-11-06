import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.08 §8: runs and their photos survive a quit, and say enough for a
/// resume to finish what it started.
@Suite struct CommonPhotosStoreTests {
    private func store() throws -> CommonPhotosStore {
        CommonPhotosStore(database: try AppDatabase.makeEmpty())
    }

    private func source(_ path: String, size: Int64 = 10, modifiedAt: Int? = 1) -> CommonPhotosItem.Source {
        CommonPhotosItem.Source(path: path, size: size, modifiedAt: modifiedAt)
    }

    @Test func roundTrip() throws {
        let store = try store()
        let run = CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["photos/Tuấn", "photos/Vợ"],
                                  destination: "photos/Shared", action: .move, createdAt: 100)
        var a = CommonPhotosItem(runId: "R1", position: 0, sha256: "aa", size: 10,
                                 sources: [source("photos/Tuấn/a.jpg"), source("photos/Vợ/a.jpg")], updatedAt: 100)
        a.sources[0].sidecar = "photos/Tuấn/a.xmp"
        let b = CommonPhotosItem(runId: "R1", position: 1, sha256: "bb", size: 20,
                                 sources: [source("photos/Tuấn/b.jpg", size: 20), source("photos/Vợ/x/b.jpg", size: 20, modifiedAt: nil)],
                                 status: .failed, reason: CommonPhotosItem.reason(.checksumMismatch), updatedAt: 100)
        try store.start(run, items: [a, b])

        // Before the rename: where it goes and what is renamed are known.
        a.status = .moving
        a.destinationPath = "photos/Shared/a.jpg"
        a.movedFrom = "photos/Tuấn/a.jpg"
        try store.update(a, now: 200)
        a.updatedAt = 200

        #expect(try store.run(id: "R1") == run)
        #expect(try store.items(runId: "R1") == [a, b])
    }

    @Test func partPathAndRemovedSourcesRoundTrip() throws {
        let store = try store()
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy),
                        items: [CommonPhotosItem(runId: "R1", position: 0, sha256: "aa", size: 1,
                                                 sources: [source("A/a"), source("B/a")], updatedAt: 1)])
        var item = try #require(try store.items(runId: "R1").first)
        item.status = .copying
        item.partPath = "C/a.shotdex-part"
        item.sources[1].isRemoved = true
        try store.update(item, now: 1)

        let read = try #require(try store.items(runId: "R1").first)
        #expect(read.partPath == "C/a.shotdex-part")
        #expect(read.sources.map(\.isRemoved) == [false, true])
        #expect(!read.isDone)
    }

    @Test func unfinishedRuns() throws {
        let store = try store()
        for (id, createdAt) in [("old", 1), ("new", 2), ("done", 3), ("last", 4), ("halted", 5)] {
            try store.start(CommonPhotosRun(id: id, connectionId: "S1", folders: ["A", "B"], destination: "C",
                                            action: .copy, createdAt: createdAt), items: [])
        }
        try store.markState(.paused, runId: "old", now: 9)
        try store.markState(.finished, runId: "done", csvPath: "C/log.csv")
        try store.markState(.finished, runId: "done")
        try store.markState(.finishing, runId: "last")
        try store.markState(.stopped, runId: "halted")

        #expect(try store.unfinishedRuns().map(\.id) == ["last", "new", "old"])
        #expect(try store.run(id: "old")?.updatedAt == 9)
        // A later state change without a CSV keeps the one written.
        #expect(try store.run(id: "done")?.csvPath == "C/log.csv")
    }

    @Test func discardTakesTheLog() throws {
        let store = try store()
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy),
                        items: [CommonPhotosItem(runId: "R1", position: 0, sha256: "aa", size: 1, sources: [source("A/a"), source("B/a")])])

        try store.discard(runId: "R1")

        #expect(try store.run(id: "R1") == nil)
        #expect(try store.items(runId: "R1").isEmpty)
    }

    /// A runner still going after Discard hears that its run is gone.
    @Test func writesToADiscardedRunThrow() throws {
        let store = try store()
        let item = CommonPhotosItem(runId: "R1", position: 0, sha256: "aa", size: 1, sources: [source("A/a"), source("B/a")])
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy),
                        items: [item])
        try store.discard(runId: "R1")

        #expect(throws: CommonPhotosStore.RunMissing(runId: "R1")) { try store.update(item) }
        #expect(throws: CommonPhotosStore.RunMissing(runId: "R1")) { try store.markState(.paused, runId: "R1") }
    }

    /// One unreadable value keeps the row: the run is still listed so it can
    /// be discarded, and is never resumed — a Move must not come back as a
    /// Copy.
    @Test func unreadableRunIsDiscardOnly() throws {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO common_photo_runs (id, connectionId, folders, destination, action, state, createdAt, updatedAt)
                VALUES ('R1', 'S1', 'not json', 'C', 'teleport', 'dreaming', 1, 1)
                """)
        }
        let store = CommonPhotosStore(database: database)

        let run = try #require(try store.run(id: "R1"))

        #expect(try store.unfinishedRuns().map(\.id) == ["R1"])
        #expect(run.isUnfinished)
        #expect(!run.canResume)
    }

    /// Unreadable sources fail the photo with a reason; an unknown status
    /// redoes it.
    @Test func unreadableItemValues() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosStore(database: database)
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .move), items: [])
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO common_photo_items (runId, position, sha256, size, sources, status, updatedAt)
                VALUES ('R1', 0, 'aa', 1, 'garbage', 'placed', 1),
                       ('R1', 1, 'bb', 1, '[{"path":"A/b","size":1,"isRemoved":false}]', 'levitating', 1)
                """)
        }

        let items = try store.items(runId: "R1")

        #expect(items.map(\.status) == [.failed, .pending])
        #expect(items[0].failure?.reason == .unreadableRecord)
        #expect(items[1].sources.map(\.path) == ["A/b"])
    }

    /// Clear Local Metadata Index leaves runs alone (FS-19.08 §8): an
    /// unfinished Move must not forget what it still has to remove.
    @Test func clearingTheIndexKeepsRuns() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosStore(database: database)
        try store.start(CommonPhotosRun(id: "R1", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .move),
                        items: [CommonPhotosItem(runId: "R1", position: 0, sha256: "aa", size: 1, sources: [source("A/a"), source("B/a")])])

        try MetadataStore(database: database).deleteAll()

        #expect(try store.run(id: "R1") != nil)
        #expect(try store.items(runId: "R1").count == 1)
    }

    // MARK: Undo (FS-19.08 §6b)

    private func finishedRun(_ store: CommonPhotosStore, id: String, createdAt: Int = 1,
                             statuses: [CommonPhotosItem.Status] = [.copied, .skipped, .copied, .failed]) throws {
        let items = statuses.enumerated().map { index, status in
            var item = CommonPhotosItem(runId: id, position: index, sha256: "s\(index)", size: 10,
                                        sources: [source("A/\(index).jpg"), source("B/\(index).jpg")], status: status,
                                        destinationPath: "C/\(index).jpg", updatedAt: 1)
            if index == 0 {
                item.sidecarPlaced = "C/0.xmp"
                item.sidecarSHA256 = "x0"
            }
            return item
        }
        try store.start(CommonPhotosRun(id: id, connectionId: "S1", folders: ["A", "B"], destination: "C",
                                        action: .copy, createdAt: createdAt), items: items)
        try store.markState(.finished, runId: id, now: createdAt)
    }

    /// An undo is a run of its own over the Copied and Moved rows, each a
    /// waiting copy keeping its position and what the run recorded.
    @Test func undoRunCopiesUndoableRows() throws {
        let store = try store()
        try finishedRun(store, id: "R1")

        let undo = try store.startUndo(of: "R1", id: "U1", now: 50)

        #expect(undo.undoOf == "R1")
        #expect(undo.action == .copy && undo.destination == "C" && undo.folders == ["A", "B"])
        #expect(try store.run(id: "U1")?.undoOf == "R1")
        let items = try store.items(runId: "U1")
        #expect(items.map(\.position) == [0, 2])
        #expect(items.allSatisfy { $0.status == .pending && $0.reason == nil })
        #expect(items[0].sidecarPlaced == "C/0.xmp" && items[0].sidecarSHA256 == "x0")
        #expect(items[0].destinationPath == "C/0.jpg")
        // The run's own rows are untouched until the undo does its work.
        #expect(try store.items(runId: "R1").map(\.status) == [.copied, .skipped, .copied, .failed])
        #expect(try store.unfinishedRuns().map(\.id) == ["U1"])
    }

    @Test func undoSelectedRowsOnly() throws {
        let store = try store()
        try finishedRun(store, id: "R1")

        try store.startUndo(of: "R1", positions: [1, 2], id: "U1")

        // Row 1 is Skipped: never undone.
        #expect(try store.items(runId: "U1").map(\.position) == [2])
    }

    @Test func undoRefusals() throws {
        let store = try store()
        try store.start(CommonPhotosRun(id: "going", connectionId: "S1", folders: ["A", "B"], destination: "C", action: .copy),
                        items: [CommonPhotosItem(runId: "going", position: 0, sha256: "a", size: 1, sources: [source("A/a")], status: .copied)])
        #expect(throws: CommonPhotosStore.UndoRefusal.notOver) { try store.startUndo(of: "going") }

        try finishedRun(store, id: "R1", statuses: [.skipped, .failed])
        #expect(throws: CommonPhotosStore.UndoRefusal.nothingToUndo) { try store.startUndo(of: "R1") }

        try finishedRun(store, id: "R2")
        try store.startUndo(of: "R2", positions: [0], id: "U1")
        // One undo at a time per run; an undo is never undone.
        #expect(throws: CommonPhotosStore.UndoRefusal.undoUnfinished) { try store.startUndo(of: "R2", positions: [2]) }
        try store.markState(.finished, runId: "U1")
        #expect(throws: CommonPhotosStore.UndoRefusal.notOver) { try store.startUndo(of: "U1") }
        #expect(try store.startUndo(of: "R2", positions: [2]).undoOf == "R2")
    }

    /// AC-142: 20 finished runs are kept; the 21st pushes out the oldest with
    /// its log and its undo runs. A run not over is never pushed out, and
    /// lists past a restart.
    @Test func keepsTwentyFinishedRuns() throws {
        let store = try store()
        try finishedRun(store, id: "old", createdAt: 1)
        try store.startUndo(of: "old", id: "old-undo", now: 2)
        try store.markState(.finished, runId: "old-undo", now: 2)
        try store.start(CommonPhotosRun(id: "halted", connectionId: "S1", folders: ["A", "B"], destination: "C",
                                        action: .copy, createdAt: 0), items: [])
        try store.markState(.paused, runId: "halted")
        for index in 2...20 { try finishedRun(store, id: "R\(index)", createdAt: index + 10) }
        #expect(try store.keptRuns().count == 21)   // 20 groups: old + its undo, R2…R20
        #expect(try store.run(id: "old") != nil)

        try finishedRun(store, id: "R21", createdAt: 100)

        #expect(try store.run(id: "old") == nil)
        #expect(try store.run(id: "old-undo") == nil)
        #expect(try store.items(runId: "old").isEmpty)
        #expect(try store.run(id: "halted") != nil)
        let recent = try store.keptRuns()
        #expect(recent.count == 20)
        #expect(recent.first?.id == "R21")
        #expect(!recent.contains { $0.id == "halted" })
    }

    /// v47 columns round-trip.
    @Test func undoColumnsRoundTrip() throws {
        let store = try store()
        try finishedRun(store, id: "R1")
        let read = try #require(try store.items(runId: "R1").first)
        #expect(read.sidecarPlaced == "C/0.xmp")
        #expect(read.sidecarSHA256 == "x0")
        #expect(try store.run(id: "R1")?.undoOf == nil)
    }

    /// A group with an undo still going is kept past the cut, and a stop
    /// makes room as a finish does.
    @Test func unfinishedUndoKeepsItsGroup() throws {
        let store = try store()
        try finishedRun(store, id: "old", createdAt: 1)
        try store.startUndo(of: "old", id: "old-undo", now: 2)
        try store.markState(.paused, runId: "old-undo")
        for index in 2...21 { try finishedRun(store, id: "R\(index)", createdAt: index + 10) }
        try store.start(CommonPhotosRun(id: "last", connectionId: "S1", folders: ["A", "B"], destination: "C",
                                        action: .copy, createdAt: 99), items: [])
        try store.markState(.stopped, runId: "last")

        #expect(try store.run(id: "old") != nil)
        #expect(try store.run(id: "old-undo") != nil)
        // 21 over groups besides "old": R2 went when "last" stopped.
        #expect(try store.run(id: "R2") == nil)
        #expect(try store.run(id: "R3") != nil)
    }

    /// Runs started in the same second go in the order they were made.
    @Test func sameSecondRunsKeepTheirOrder() throws {
        let store = try store()
        for index in 0...20 { try finishedRun(store, id: "R\(index)", createdAt: 5) }

        #expect(try store.run(id: "R0") == nil)
        #expect(try store.keptRuns().map(\.id) == (1...20).reversed().map { "R\($0)" })
    }

    @Test func undoOfRowsThatCannotBeUndoneIsRefused() throws {
        let store = try store()
        try finishedRun(store, id: "R1")
        #expect(throws: CommonPhotosStore.UndoRefusal.nothingToUndo) { try store.startUndo(of: "R1", positions: [1, 3, 9]) }

        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO common_photo_runs (id, connectionId, folders, destination, action, state, createdAt, updatedAt)
                VALUES ('R1', 'S1', 'not json', 'C', 'copy', 'finished', 1, 1)
                """)
        }
        #expect(throws: CommonPhotosStore.UndoRefusal.notOver) { try CommonPhotosStore(database: database).startUndo(of: "R1") }
    }

    /// Remove from List takes the run's undo runs, their photos and the
    /// history records along.
    @Test func discardTakesItsUndoRuns() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosStore(database: database)
        try finishedRun(store, id: "R1")
        try store.startUndo(of: "R1", id: "U1")
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO common_photo_history_moves (runId, historyTable, rowId, sourcePath, pathBefore, pathAfter)
                VALUES ('R1', 'server_uploads', '1', 'B/0.jpg', 'B/0.jpg', 'C/0.jpg')
                """)
        }

        try store.discard(runId: "R1")

        #expect(try store.run(id: "U1") == nil)
        #expect(try store.items(runId: "U1").isEmpty)
        #expect(try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM common_photo_history_moves") } == 0)
    }
}
