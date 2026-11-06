import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-06.10 AC-6, AC-7 — the answers live in a table of their own, and a
/// pass carries on from where it stopped.
@MainActor
struct OriginalPresenceStoreTests {
    private static func library(_ count: Int) throws -> (AppDatabase, [String]) {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<count).map { String(format: "p%03d", $0) }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) },
            cursorAssetId: nil
        )
        return (database, ids)
    }

    /// AC-6: a pass that stopped after 300 of 500 items, picked up again by a
    /// fresh store (the app was killed), asks only for the 200 left.
    @Test func passCarriesOnAfterTheAppIsKilled() throws {
        let (database, ids) = try Self.library(500)
        let store = OriginalPresenceStore(database: database)
        try store.beginPass(at: 1_000)
        for _ in 0..<3 {
            let batch = try store.nextBatch(since: 1_000, limit: 100)
            #expect(batch.count == 100)
            try store.record(Dictionary(uniqueKeysWithValues: batch.map { ($0, .onDevice) }), at: 1_001)
        }

        let reopened = OriginalPresenceStore(database: database)
        let pass = try #require(try reopened.pass())
        #expect(pass.startedAt == 1_000 && pass.finishedAt == nil)
        let rest = try reopened.nextBatch(since: pass.startedAt, limit: 1_000)
        #expect(rest.count == 200)
        #expect(Set(rest).isDisjoint(with: Set(ids.prefix(300))))
        #expect(try reopened.progress(since: pass.startedAt) == .init(checked: 300, total: 500))
    }

    /// AC-7: indexing every photo again leaves every answer where it was.
    @Test func reindexKeepsTheAnswers() throws {
        let (database, ids) = try Self.library(50)
        let store = OriginalPresenceStore(database: database)
        try store.record(Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0 % 2 == 0 ? .onDevice : .iCloudOnly) }), at: 10)

        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_800_000_000 + $0) },
            cursorAssetId: nil
        )

        #expect(try store.state(of: "p000") == .onDevice)
        #expect(try store.state(of: "p001") == .iCloudOnly)
        #expect(try store.progress(since: 10).checked == 50)
    }

    /// A new pass is due for every row older than its start, items never
    /// checked first.
    @Test func newPassRechecksOldRowsNeverCheckedFirst() throws {
        let (database, ids) = try Self.library(6)
        let store = OriginalPresenceStore(database: database)
        try store.record(Dictionary(uniqueKeysWithValues: ids.prefix(4).map { ($0, .onDevice) }), at: 10)
        try store.beginPass(at: 20)
        #expect(try store.nextBatch(since: 20, limit: 10) == ["p004", "p005", "p000", "p001", "p002", "p003"])
        #expect(try store.nextBatch(since: 5, limit: 10) == ["p004", "p005"])
    }

    /// AC-8 at the store: a changed item loses its answer and goes to the
    /// front of the line.
    @Test func markForRecheckClearsTheAnswer() throws {
        let (database, ids) = try Self.library(3)
        let store = OriginalPresenceStore(database: database)
        try store.record(Dictionary(uniqueKeysWithValues: ids.map { ($0, .onDevice) }), at: 10)
        try store.markForRecheck(["p001"])
        #expect(try store.state(of: "p001") == nil)
        #expect(try store.state(of: "p000") == .onDevice)
        #expect(try store.nextBatch(since: 5, limit: 10) == ["p001"])
    }

    /// "Could not tell" moves the pass on but leaves the item unchecked.
    @Test func unknownIsLookedAtButUnchecked() throws {
        let (database, _) = try Self.library(2)
        let store = OriginalPresenceStore(database: database)
        try store.record(["p000": nil, "p001": .iCloudOnly], at: 10)
        #expect(try store.state(of: "p000") == nil)
        #expect(try store.nextBatch(since: 10, limit: 10).isEmpty)
    }

    @Test func finishPassIsRecorded() throws {
        let (database, _) = try Self.library(1)
        let store = OriginalPresenceStore(database: database)
        #expect(try store.pass() == nil)
        try store.beginPass(at: 5)
        try store.finishPass(at: 9)
        #expect(try store.pass() == .init(startedAt: 5, finishedAt: 9))
        try store.beginPass(at: 12)
        #expect(try store.pass() == .init(startedAt: 12, finishedAt: nil))
    }

    /// AC-6 on disk: the pass row and the answers survive closing and
    /// reopening the database file — all a pass needs to carry on. (The
    /// runner that drives it lands with T6.)
    @Test func passSurvivesReopeningTheDatabaseFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("original-presence-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let database = try AppDatabase(DatabaseQueue(path: url.path))
            let ids = (0..<500).map { String(format: "p%03d", $0) }
            try MetadataStore(database: database).saveBatch(
                ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)
            let store = OriginalPresenceStore(database: database)
            try store.beginPass(at: 1_000)
            try store.record(Dictionary(uniqueKeysWithValues: ids.prefix(300).map { ($0, .onDevice) }), at: 1_001)
        }
        let reopened = OriginalPresenceStore(database: try AppDatabase(DatabaseQueue(path: url.path)))
        #expect(try reopened.pass() == .init(startedAt: 1_000, finishedAt: nil))
        #expect(try reopened.nextBatch(since: 1_000, limit: 1_000).count == 200)
        #expect(try reopened.progress(since: 1_000) == .init(checked: 300, total: 500))
    }

    /// AC-9's total: hidden and recently deleted photos are neither asked
    /// for nor counted, and a photo with a NAS copy too is asked for once.
    @Test func batchAndProgressSkipWhatTheGridDoesNotShow() throws {
        let (database, _) = try Self.library(5)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 1 WHERE photoId = 'p001'")
            try db.execute(sql: "UPDATE photo_copies SET missingSince = 5 WHERE photoId = 'p002'")
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, lastSeenAt)
                VALUES ('server:p003', 'p003', 'S1', 'server', 'a/p003.heic', 'a/p003.heic', 1)
                """)
        }
        let store = OriginalPresenceStore(database: database)
        #expect(try store.nextBatch(since: 0, limit: 10) == ["p000", "p003", "p004"])
        try store.record(["p000": .onDevice, "p001": .onDevice], at: 10)
        #expect(try store.progress(since: 10) == .init(checked: 1, total: 3))
        #expect(try store.nextBatch(since: 10, limit: 10) == ["p003", "p004"])
    }

    /// A row written in the second the pass started counts as looked at;
    /// one a second older is still due.
    @Test func recordAtPassStartCountsAsChecked() throws {
        let (database, _) = try Self.library(2)
        let store = OriginalPresenceStore(database: database)
        try store.beginPass(at: 50)
        try store.record(["p000": .onDevice], at: 50)
        try store.record(["p001": .onDevice], at: 49)
        #expect(try store.nextBatch(since: 50, limit: 10) == ["p001"])
        #expect(try store.progress(since: 50).checked == 1)
    }

    /// A photo removed from Photos takes its answer with it; one that comes
    /// back is checked afresh.
    @Test func deletedAssetLosesItsAnswer() throws {
        let (database, _) = try Self.library(2)
        let store = OriginalPresenceStore(database: database)
        try store.record(["p000": .onDevice, "p001": .iCloudOnly], at: 10)
        try MetadataStore(database: database).deleteAssets(ids: ["p001"])
        #expect(try store.state(of: "p001") == nil)
        #expect(try store.state(of: "p000") == .onDevice)
        try MetadataStore(database: database).saveBatch([PhotoMarksStoreTests.record("p001")], cursorAssetId: nil)
        #expect(try store.nextBatch(since: 10, limit: 10) == ["p001"])
    }
}
