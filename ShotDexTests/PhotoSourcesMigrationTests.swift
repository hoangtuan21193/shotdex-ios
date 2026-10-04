import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §1, §3 — v30 gives every photo an id and a Photos copy without
/// rewriting a single row the user's data hangs off.
@Suite struct PhotoSourcesMigrationTests {
    /// AC-69: a database from the build before (v29) holds ids in many
    /// tables — indexed photos, and a flag on an asset never indexed under
    /// `.limited` access. After v30 each id is one photo with one Photos copy
    /// whose id is the asset id; the satellite rows are untouched; the new
    /// tables and their indexes exist; duplicate groups are per source.
    @Test func backfillsUnionOfIds() throws {
        let queue = try DatabaseQueue()
        var migrator = AppDatabase.migrator
        // The debug erase-on-change guard would wipe what is written between
        // the two migrate calls.
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v29-creationDrafts")

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus)
                VALUES ('A', ?, 0, 0, 'indexed'), ('D', ?, 0, 0, 'indexed')
                """, arguments: [MediaKind.photo.storedValue, MediaKind.photo.storedValue])
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('limited', 'reject', 1), ('A', 'pick', 2)")
            try db.execute(sql: "INSERT INTO pending_photo_rating (assetId, rating, ratedAt) VALUES ('B', 4, 3)")
            try db.execute(sql: "INSERT INTO photo_caption (assetId, caption, foldKey) VALUES ('C', 'Kyoto', 'kyoto')")
            try db.execute(sql: "INSERT INTO raw_pair_assets (assetId) VALUES ('R')")
            try db.execute(sql: "INSERT INTO perceptual_hash (assetId, hash, computedAt) VALUES ('P', 7, 4)")
            try db.execute(sql: "INSERT INTO duplicate_groups (strictness, groupId, assetId) VALUES ('exact', 'g1', 'D'), ('exact', 'g1', 'A')")
            try db.execute(sql: "INSERT INTO duplicate_scan_state (strictness, scannedAt, groupCount) VALUES ('exact', 5, 1)")
        }

        try migrator.migrate(queue)

        try queue.read { db in
            let ids = Set(try String.fetchAll(db, sql: "SELECT id FROM photos"))
            #expect(ids == ["A", "B", "C", "D", "P", "R", "limited"])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL") == 0)

            let copies = try Row.fetchAll(db, sql: "SELECT id, photoId, sourceId, kind, photoKitId FROM photo_copies")
            #expect(copies.count == ids.count)
            for copy in copies {
                let photoId: String = copy["photoId"]
                #expect(copy["id"] as String == "photos:\(photoId)")
                #expect(copy["photoKitId"] as String? == photoId)
                #expect(copy["sourceId"] as String == PhotoLibrarySource.id)
                #expect(copy["kind"] as String == "photos")
            }
            #expect(try String.fetchAll(db, sql: "SELECT kind FROM sources") == ["photos"])

            // Satellite rows keep their ids — nothing rewritten.
            #expect(try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = 'limited'") == "reject")
            #expect(try Int.fetchOne(db, sql: "SELECT rating FROM pending_photo_rating WHERE assetId = 'B'") == 4)

            // Cached duplicate groups are a scan result: rebuilt per source.
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM duplicate_groups") == 0)
            #expect(try db.columns(in: "duplicate_groups").map(\.name).contains("sourceId"))
            #expect(try db.primaryKey("duplicate_scan_state").columns == ["strictness", "sourceId"])

            for table in ["sources", "photos", "photo_copies", "content_hashes", "photo_aliases", "photo_recipes",
                          "photo_user_marks", "photo_user_keyword", "pending_sidecar", "shotdex_albums", "shotdex_album_members"] {
                #expect(try db.tableExists(table), "\(table)")
            }
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            for index in ["photos_orphanedAt", "photo_copies_path", "photo_copies_photoKit", "photo_copies_source_photo",
                          "photo_copies_photo_online", "content_hashes_fast", "content_hashes_full"] {
                #expect(indexes.contains(index), "\(index)")
            }
        }
    }

    /// The index keeps the Photos copy in step: a new asset gets a photo and
    /// a copy; a deleted asset loses its copy, while the photo row — where its
    /// flags and stars hang — stays (the orphan rule decides later).
    @MainActor @Test func indexAddsAndRemovesThePhotosCopy() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch([PhotoMarksStoreTests.record("N1"), PhotoMarksStoreTests.record("N2")], cursorAssetId: nil)
        try metadata.saveBatch([PhotoMarksStoreTests.record("N1")], cursorAssetId: nil)

        #expect(try ids("SELECT id FROM photos", in: database) == ["N1", "N2"])
        #expect(try ids("SELECT photoKitId FROM photo_copies", in: database) == ["N1", "N2"])

        try metadata.deleteAssets(ids: ["N2"])
        #expect(try ids("SELECT id FROM photos", in: database) == ["N1", "N2"])
        #expect(try ids("SELECT photoKitId FROM photo_copies", in: database) == ["N1"])
    }

    private func ids(_ sql: String, in database: AppDatabase) throws -> Set<String> {
        try database.reader.read { db in try Set(String.fetchAll(db, sql: sql)) }
    }
}
