import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §2–§3 — what the user typed lives in tables the indexer never
/// rewrites, keyed by the photo id.
@MainActor
@Suite struct PhotoUserDataTests {
    /// AC-70: a photo with a recipe, stars, keyword, a ShotDex album, a
    /// pending sidecar write, an alias and a hidden copy goes through a full
    /// re-index and then Clear Local Metadata Index plus a fresh index. Every
    /// one of those rows is still there, byte for byte; the photo and its
    /// Photos copy too (Clear rebuilds metadata, not identity).
    @Test func userDataSurvivesReindexAndClear() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch([PhotoMarksStoreTests.record("A")], cursorAssetId: nil)

        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_recipes (photoId, recipe, updatedAt) VALUES ('A', x'01020304', 10)")
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt, title, titleAt) VALUES ('A', 4, 11, 'Fushimi', 12)")
            try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES ('A', 'Kyoto', 'kyoto', 'kyoto', 13)")
            try db.execute(sql: "INSERT INTO shotdex_albums (id, name, position, createdAt) VALUES ('al1', 'Trip', 0, 14)")
            try db.execute(sql: "INSERT INTO shotdex_album_members (albumId, photoId, addedAt) VALUES ('al1', 'A', 15)")
            try db.execute(sql: "INSERT INTO pending_sidecar (copyId, photoId, reason, markedAt) VALUES ('photos:A', 'A', 'rating', 16)")
            try db.execute(sql: "INSERT INTO photo_aliases (loserId, winnerId, mergedAt) VALUES ('old', 'A', 17)")
            try db.execute(sql: "UPDATE photo_copies SET isHidden = 1 WHERE photoId = 'A'")
        }
        let before = try snapshot(database)

        try metadata.saveBatch([PhotoMarksStoreTests.record("A")], cursorAssetId: nil)
        #expect(try snapshot(database) == before)

        try metadata.deleteAll()
        try metadata.saveBatch([PhotoMarksStoreTests.record("A")], cursorAssetId: nil)
        #expect(try snapshot(database) == before)
    }

    /// Every user-data row of the FS-19 tables, and the identity rows, as text.
    private func snapshot(_ database: AppDatabase) throws -> [String] {
        try database.reader.read { db in
            var out: [String] = []
            for (table, columns) in [
                ("photos", "id, createdAt, orphanedAt"),
                ("photo_copies", "id, photoId, sourceId, kind, photoKitId, isHidden"),
                ("photo_recipes", "photoId, hex(recipe), updatedAt"),
                ("photo_user_marks", "photoId, rating, ratingAt, title, titleAt"),
                ("photo_user_keyword", "photoId, keyword, addedAt"),
                ("shotdex_albums", "id, name, position"),
                ("shotdex_album_members", "albumId, photoId, addedAt"),
                ("pending_sidecar", "copyId, photoId, reason, markedAt"),
                ("photo_aliases", "loserId, winnerId, mergedAt"),
            ] {
                for row in try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table) ORDER BY 1, 2") {
                    out.append("\(table): \(row.description)")
                }
            }
            return out
        }
    }
}
