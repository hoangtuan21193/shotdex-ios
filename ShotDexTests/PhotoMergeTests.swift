import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.05 §4 — two photos found to be one picture become one.
@MainActor
@Suite struct PhotoMergeTests {
    /// AC-65: file photo F (★2 at 09:00, keyword "Kyoto", album "Trip", a
    /// pending sidecar write) and Photos photo P (★5 at 10:00, keyword
    /// "Temple" in Photos, Picked) are identical. The merge keeps P's older
    /// id, ★5, Picked, both keywords, the album place, the pending write
    /// re-pointed; F's id resolves to P through an alias; every satellite
    /// table that held both ids holds only P — and it all runs in one
    /// transaction (a failure leaves both photos untouched).
    @Test func collisionsInEverySatelliteTable() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([PhotoMarksStoreTests.record("P")], cursorAssetId: nil)
        let nine = 1_790_000_000 + 9 * 3600, ten = nine + 3600
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photos SET createdAt = 100 WHERE id = 'P'")
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('F', 200)")
            try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES ('c-F', 'F', 'src', 'file', 'Kyoto/F.ARW', 'kyoto/f.arw')")
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES ('F', 2, ?)", arguments: [nine])
            try db.execute(sql: "INSERT INTO photo_user_keyword (photoId, keyword, caseKey, foldKey, addedAt) VALUES ('F', 'Kyoto', 'kyoto', 'kyoto', 1)")
            try db.execute(sql: "INSERT INTO shotdex_albums (id, name, position, createdAt) VALUES ('trip', 'Trip', 0, 1)")
            try db.execute(sql: "INSERT INTO shotdex_album_members (albumId, photoId, addedAt) VALUES ('trip', 'F', 1)")
            try db.execute(sql: "INSERT INTO pending_sidecar (copyId, photoId, reason, markedAt) VALUES ('c-F', 'F', 'rating', 1)")
            try db.execute(sql: "INSERT INTO pending_photo_rating (assetId, rating, ratedAt) VALUES ('P', 5, ?)", arguments: [ten])
            try db.execute(sql: "INSERT INTO photo_keyword (assetId, keyword, caseKey, foldKey) VALUES ('P', 'Temple', 'temple', 'temple')")
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('P', 'pick', 5)")
            try db.execute(sql: "INSERT INTO photo_aliases (loserId, winnerId, mergedAt) VALUES ('older-loser', 'F', 1)")
        }

        let result = try PhotoIdentityStore(database: database).merge("F", "P")
        #expect(result.winnerId == "P")

        let state = try database.reader.read { db in
            (photos: try String.fetchAll(db, sql: "SELECT id FROM photos ORDER BY id"),
             copies: try String.fetchAll(db, sql: "SELECT photoId FROM photo_copies ORDER BY id"),
             rating: try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = 'P'"),
             pending: try Int.fetchOne(db, sql: "SELECT rating FROM pending_photo_rating WHERE assetId = 'P'"),
             flag: try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = 'P'"),
             keywords: try String.fetchAll(db, sql: "SELECT keyword FROM photo_user_keyword WHERE photoId = 'P' ORDER BY keyword"),
             albums: try String.fetchAll(db, sql: "SELECT photoId FROM shotdex_album_members"),
             sidecar: try String.fetchAll(db, sql: "SELECT photoId FROM pending_sidecar"),
             aliases: try Row.fetchAll(db, sql: "SELECT loserId, winnerId FROM photo_aliases ORDER BY loserId").map { "\($0["loserId"] as String)→\($0["winnerId"] as String)" },
             leftovers: try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM photo_user_marks WHERE photoId = 'F')
                     + (SELECT COUNT(*) FROM photo_user_keyword WHERE photoId = 'F')
                     + (SELECT COUNT(*) FROM shotdex_album_members WHERE photoId = 'F')
                """))
        }
        #expect(state.photos == ["P"])
        #expect(state.copies == ["P", "P"])
        #expect(state.rating == 5)
        #expect(state.pending == 5)
        #expect(state.flag == "pick")
        #expect(state.keywords == ["Kyoto", "Temple"])
        #expect(state.albums == ["P"])
        #expect(state.sidecar == ["P"])
        #expect(state.aliases == ["F→P", "older-loser→P"])
        #expect(state.leftovers == 0)
    }

    /// Latest change wins per field; on a tie the surviving id's value.
    @Test func latestWinsPerField() {
        let older = PhotoMergePlan.Side(id: "A", createdAt: 1, data: PhotoUserData(
            rating: Stamped(value: 3, at: 50), title: Stamped(value: "Gion", at: 10), keywords: ["Kyoto"]))
        let newer = PhotoMergePlan.Side(id: "B", createdAt: 2, data: PhotoUserData(
            rating: Stamped(value: 1, at: 40), title: Stamped(value: "Gion at night", at: 20), keywords: ["Night"]))
        let merged = PhotoMergePlan.merge(newer, older)
        #expect(merged.winnerId == "A")
        #expect(merged.data.rating?.value == 3)
        #expect(merged.data.title?.value == "Gion at night")
        #expect(merged.data.keywords == ["Kyoto", "Night"])
        #expect(PhotoMergePlan.latest(Stamped(value: 1, at: 5), Stamped(value: 2, at: 5))?.value == 1)
    }
}
