import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §3, FS-19.05 §3 — a photo is hidden only when every copy is.
@Suite struct HiddenCopyTests {
    /// AC-68: photo A is on NAS Home and on NAS Office. Hiding the NAS Home
    /// copy keeps A in the grid and Statistics but takes it out of NAS
    /// Home's view; hiding the NAS Office copy too takes A out of the grid
    /// into the Hidden section; Unhide brings both copies back.
    @Test func hiddenOnlyWhenEveryCopyHidden() throws {
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let home = try sources.addServer(name: "NAS Home", connectionId: "C1")
        let office = try sources.addServer(name: "NAS Office", connectionId: "C2")
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('A', 1)")
            try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus) VALUES ('A', 1, 0, 1, 'indexed')")
            for (copy, source) in [("A-home", home), ("A-office", office)] {
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES (?, 'A', ?, 'server', 'A.ARW', 'a.arw')",
                               arguments: [copy, source])
            }
        }
        let hidden = HiddenCopyStore(database: database)
        let grid = LibraryQueries(database: database)
        let statistics = StatisticsQueries(database: database)

        try hidden.hide(copyIds: ["A-home"])
        #expect(try grid.count(matching: FilterCriteria()) == 1)
        #expect(try statistics.totalPhotos(scope: .allTime) == 1)
        #expect(try hidden.photoIds(inSource: home).isEmpty)
        #expect(try hidden.photoIds(inSource: office) == ["A"])
        #expect(try hidden.hiddenPhotoIds().isEmpty)

        try hidden.hide(copyIds: ["A-office"])
        #expect(try grid.count(matching: FilterCriteria()) == 0)
        #expect(try statistics.totalPhotos(scope: .allTime) == 0)
        #expect(try hidden.hiddenPhotoIds() == ["A"])

        try hidden.unhide(photoIds: ["A"])
        #expect(try grid.count(matching: FilterCriteria()) == 1)
        #expect(try hidden.photoIds(inSource: home) == ["A"])
        #expect(try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE isHidden = 1") } == 0)
    }

    /// K6 gate (FS-19 plan, board A5): the visibility rule is an EXISTS per
    /// row. At 55,000 photos with 60,000 copies, counting the grid and
    /// reading its first page each stay well under a frame budget's worth
    /// of seconds on the simulator.
    @Test func visibilityAt55k() async throws {
        let database = try AppDatabase.makeEmpty()
        let nas = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        try await database.writer.write { db in
            try db.execute(sql: """
                WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i < 54999)
                INSERT INTO photo_metadata (assetId, creationDate, mediaType, isFavorite, indexedAt, exifStatus)
                SELECT 'P' || i, 1700000000 + i, 1, 0, 1, 'indexed' FROM n
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO photo_copies (id, photoId, sourceId, kind, photoKitId)
                SELECT 'photos:' || assetId, assetId, 'photos-library', 'photos', assetId FROM photo_metadata
                """)
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isHidden)
                SELECT 'nas:' || assetId, assetId, ?, 'server', assetId || '.ARW', lower(assetId) || '.arw', 1
                FROM photo_metadata WHERE creationDate % 11 = 0
                """, arguments: [nas])
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 1 WHERE kind = 'photos' AND photoId IN (SELECT assetId FROM photo_metadata WHERE creationDate % 11 = 0)")
        }
        let grid = LibraryQueries(database: database)
        let clock = ContinuousClock()
        var count = 0
        let counting = try clock.measure { count = try grid.count(matching: FilterCriteria()) }
        var page: [LibraryGridItem] = []
        let paging = try await clock.measure { page = try await grid.gridItems(matching: FilterCriteria(), sort: .dateTakenNewest, limit: 600) }
        #expect(count == 55_000 - 5_000)
        #expect(page.count == 600)
        print("K6 visibility at 55k: count \(counting), first page \(paging)")
        #expect(counting < .milliseconds(500))
        #expect(paging < .milliseconds(500))
    }
}
