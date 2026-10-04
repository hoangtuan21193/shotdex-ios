import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §4 — a merged-away id still finds its photo.
@MainActor
@Suite struct PhotoAliasTests {
    /// AC-66: a widget and Recents hold the id of a photo that a merge
    /// folded into another. Through the alias they find the survivor — its
    /// stars and copies — and a PhotoKit id to load, so nothing shows empty.
    /// Chains (a survivor merged again) resolve to the last survivor.
    @Test func loserIdResolves() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([PhotoMarksStoreTests.record("P")], cursorAssetId: nil)
        try database.writer.write { db in
            // The file photo is older this time, so the Photos photo loses.
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('F', 1)")
            try db.execute(sql: "UPDATE photos SET createdAt = 2 WHERE id = 'P'")
            try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES ('c-F', 'F', 's', 'file', 'F.JPG', 'f.jpg')")
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('G', 0)")
            try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES ('c-G', 'G', 's2', 'file', 'G.JPG', 'g.jpg')")
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES ('P', 4, 10)")
        }
        let store = PhotoIdentityStore(database: database)
        #expect(try store.merge("P", "F").winnerId == "F")
        let resolver = PhotoAliasResolver(database: database)
        #expect(try resolver.photoId(for: "P") == "F")
        #expect(try resolver.libraryAssetId(for: "P") == "P")
        let survivor = try resolver.photoId(for: "P")
        let stars = try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [survivor])
        }
        #expect(stars == 4)

        // F is merged into the even older G: P now leads to G.
        #expect(try store.merge("F", "G").winnerId == "G")
        #expect(try resolver.photoId(for: "P") == "G")
        #expect(try resolver.libraryAssetId(for: "P") == "P")
        #expect(try resolver.photoId(for: "never-merged") == "never-merged")
        #expect(try resolver.libraryAssetId(for: "G") == "P")
    }
}
