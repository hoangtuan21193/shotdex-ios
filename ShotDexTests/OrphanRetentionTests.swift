import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §5 and FS-01.12 AC-9 — a photo that leaves keeps its user data
/// for 30 days, never on the word of a `.limited` fetch.
@MainActor
@Suite struct OrphanRetentionTests {
    @Test func fullAccessIndexRunOrphans() {
        let changes = IndexRunChanges(changed: ["A"], deleted: ["B"], isFullWalk: false, accessIsFull: true)
        #expect(OrphanRetention.orphanIds(after: changes) == ["B"])
    }

    @Test func limitedIndexRunKeeps() {
        // C left the shared set: a full walk under `.limited` no longer finds
        // it, exactly as if it were deleted.
        let changes = IndexRunChanges(changed: [], deleted: ["C"], isFullWalk: true, accessIsFull: false)
        #expect(OrphanRetention.orphanIds(after: changes).isEmpty)
    }

    @Test func deletionFromTheAppAlwaysOrphans() {
        #expect(OrphanRetention.makesOrphans(on: .deletedInApp))
        #expect(!OrphanRetention.makesOrphans(on: .indexRun(accessIsFull: false)))
    }

    /// AC-9 below the PhotoKit line: B (Rejected, full access) is reported
    /// deleted → it leaves the Rejected count at once, but its rows wait out
    /// the 30 days; C (Rejected) is reported gone by a `.limited` run → not an
    /// orphan, still counted.
    @Test func goneFromLibraryLeavesCountsKeepsRows() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            ["B", "C", "D"].map { PhotoMarksStoreTests.record($0) }, cursorAssetId: nil)
        let store = PhotoMarksStore(database: database)
        let marks = PhotoMarks(store: store)
        await marks.setFlag(.reject, ids: ["B", "C", "D"])
        await marks.setRating(4, ids: ["B"])
        let orphans = PhotoOrphanStore(database: database)

        for changes in [
            IndexRunChanges(changed: [], deleted: ["B"], isFullWalk: false, accessIsFull: true),
            IndexRunChanges(changed: [], deleted: ["C"], isFullWalk: true, accessIsFull: false),
        ] {
            let ids = OrphanRetention.orphanIds(after: changes)
            try orphans.markGoneFromLibrary(ids: Array(ids))
            marks.forget(ids)
        }

        #expect(marks.assetIds(flagged: .reject) == ["C", "D"])
        #expect(try store.allFlags() == ["C": .reject, "D": .reject])
        #expect(try store.allPendingRatings().isEmpty)
        let kept = try await database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT assetId FROM photo_flag ORDER BY assetId")
        }
        #expect(kept == ["B", "C", "D"])
        let orphaned = try await database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM photos WHERE orphanedAt IS NOT NULL")
        }
        #expect(orphaned == ["B"])

        // B comes back (a re-index finds it): no longer an orphan, marks return.
        try MetadataStore(database: database).saveBatch([PhotoMarksStoreTests.record("B")], cursorAssetId: nil)
        #expect(try store.allFlags()["B"] == .reject)
    }

    /// AC-67: A orphaned 31 days ago with stars, a recipe, a flag, an album
    /// place, two upload rows and a download row; E orphaned 29 days ago. The
    /// launch purge removes A from every user-data table and keeps all three
    /// history rows; E keeps everything.
    @Test func purgeKeepsHistories() throws {
        let database = try AppDatabase.makeEmpty()
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let day = 24.0 * 60 * 60
        try database.writer.write { db in
            for (id, ago) in [("A", 31.0), ("E", 29.0)] {
                let stamp = Int(now.timeIntervalSince1970 - ago * day)
                try db.execute(sql: "INSERT INTO photos (id, createdAt, orphanedAt) VALUES (?, 0, ?)", arguments: [id, stamp])
                try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, 'pick', 1)", arguments: [id])
                try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [id])
                try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, x'01', 1)", arguments: [id])
                try db.execute(sql: "INSERT INTO shotdex_album_members (albumId, photoId, addedAt) VALUES ('trip', ?, 1)", arguments: [id])
                for n in 1...2 {
                    try db.execute(sql: """
                        INSERT INTO server_uploads (assetId, fileKey, serverId, serverName, remotePath, byteCount, sha256, uploadedAt)
                        VALUES (?, ?, NULL, 'NAS Home', ?, 10, 'aa', 1)
                        """, arguments: [id, "f\(n)", "Photos/\(id)\(n).ARW"])
                }
                try db.execute(sql: """
                    INSERT INTO server_downloads (assetId, serverId, serverName, remotePath, byteCount, sha256, downloadedAt)
                    VALUES (?, NULL, 'NAS Home', ?, 10, 'bb', 1)
                    """, arguments: [id, "Photos/\(id).JPG"])
            }
        }

        let purged = try PhotoOrphanStore(database: database).purge(orphanedBefore: OrphanRetention.purgeCutoff(now: now))
        #expect(purged == 1)

        let left = try database.reader.read { db in
            try [("photos", "id"), ("photo_flag", "assetId"), ("photo_user_marks", "photoId"),
                 ("photo_recipes", "photoId"), ("shotdex_album_members", "photoId")].map { table, column in
                (table, try String.fetchAll(db, sql: "SELECT \(column) FROM \(table)"))
            }
        }
        for (table, ids) in left {
            #expect(ids == ["E"], "\(table)")
        }
        let histories = try database.reader.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM server_uploads WHERE assetId = 'A'"),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM server_downloads WHERE assetId = 'A'"))
        }
        #expect(histories.0 == 2)
        #expect(histories.1 == 1)
    }

    /// AC-51: file photo A (★4, Picked, a recipe, one copy) is deleted in
    /// Finder and put back 29 days later; B has been an orphan for 31 days.
    /// After the read and the launch purge, A is back with the same id and
    /// all its data; B is gone from every table.
    @Test func thirtyDays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PutBack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("DSC04512.JPG")
        let bytes = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        try bytes.write(to: file)
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        let day = 24.0 * 60 * 60
        let start = Date(timeIntervalSince1970: 1_791_000_000)
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true, now: start)
        let a = try database.reader.read { db in try String.fetchOne(db, sql: "SELECT photoId FROM photo_copies") ?? "" }
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [a])
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, 'pick', 1)", arguments: [a])
            try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES (?, x'01', 1)", arguments: [a])
            try db.execute(sql: "INSERT INTO photos (id, createdAt, orphanedAt) VALUES ('B', 0, ?)", arguments: [Int(start.timeIntervalSince1970 - 2 * day)])
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('B', 'reject', 1)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        try FileManager.default.removeItem(at: file)
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true, now: start.addingTimeInterval(day))
        let orphaned = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT orphanedAt FROM photos WHERE id = ?", arguments: [a]) }
        #expect(orphaned != nil)

        // Put Back: same path, same bytes, same dates — 29 days later.
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate] as Any], ofItemAtPath: file.path)
        let later = start.addingTimeInterval(30 * day)
        _ = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true, now: later)
        try PhotoOrphanStore(database: database).purge(orphanedBefore: OrphanRetention.purgeCutoff(now: later))

        let state = try database.reader.read { db in
            (photos: try String.fetchAll(db, sql: "SELECT id FROM photos"),
             orphan: try Int.fetchOne(db, sql: "SELECT orphanedAt FROM photos WHERE id = ?", arguments: [a]),
             rating: try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [a]),
             flags: try String.fetchAll(db, sql: "SELECT assetId || ':' || flag FROM photo_flag"),
             recipes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_recipes WHERE photoId = ?", arguments: [a]))
        }
        #expect(state.photos == [a])
        #expect(state.orphan == nil)
        #expect(state.rating == 4)
        #expect(state.flags == ["\(a):pick"])
        #expect(state.recipes == 1)
    }
}
