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
}
