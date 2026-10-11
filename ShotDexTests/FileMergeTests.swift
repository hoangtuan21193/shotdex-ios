import CryptoKit
import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §4 — Merge when the kept photo is a file.
@Suite struct FileMergeTests {
    /// AC-60: a Similar group of two different files. B is kept (no stars,
    /// no location), C goes (★4, Picked, keyword "Kyoto", a location, taken
    /// earlier). After Merge, B is ★4, Picked and tagged "Kyoto" in the
    /// database and in its sidecar; its location and capture date are what
    /// they were, and its file's bytes are unchanged.
    @Test func ratingFlagKeywordOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileMerge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, width) in [("B.JPG", 320), ("C.JPG", 336)] {
            var options = MetadataFixture.Options()
            options.width = width
            options.starRating = nil
            try MetadataFixture.encode(.jpeg, options: options).write(to: root.appendingPathComponent(name))
        }
        let before = SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent("B.JPG")))
        let database = try AppDatabase.makeEmpty()
        let folder = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try FolderSourceIndexer(database: database, composer: ServerSourceIndexTests.composer, readsSidecars: false)
            .index(sourceId: folder, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let ids = try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT photoId FROM photo_copies WHERE sourceId = ? ORDER BY relativePath", arguments: [folder])
        }
        let (b, c) = (ids[0], ids[1])
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET latitude = NULL, longitude = NULL WHERE assetId = ?", arguments: [b])
            try db.execute(sql: "UPDATE photo_metadata SET latitude = 35.0, longitude = 135.7, creationDate = 1600000000 WHERE assetId = ?", arguments: [c])
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [c])
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, 'pick', 1)", arguments: [c])
            try PhotoUserMarksStore.addKeywords(db, ["Kyoto"], photoId: c, at: 1)
        }
        let keptRow = try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT creationDate, latitude, longitude FROM photo_metadata WHERE assetId = ?", arguments: [b])
        }

        try database.writer.write { db in try FileMerge.inherit(db, keeper: b, from: [c], at: 2) }
        _ = try SidecarWriter(database: database, fileURL: { _, path in root.appendingPathComponent(path) }, isEnabled: { true })
            .write(photoIds: [b])

        let (rating, flag, keywords) = try database.reader.read { db in
            (try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [b]),
             try String.fetchOne(db, sql: "SELECT flag FROM photo_flag WHERE assetId = ?", arguments: [b]),
             try String.fetchAll(db, sql: "SELECT keyword FROM photo_user_keyword WHERE photoId = ?", arguments: [b]))
        }
        #expect(rating == 4)
        #expect(flag == "pick")
        #expect(keywords == ["Kyoto"])
        let sidecar = try #require(SidecarReader.read(sidecarAt: SidecarWriter.sidecarURL(forImageAt: root.appendingPathComponent("B.JPG"), isPaired: false)))
        #expect(sidecar.rating == 4)
        #expect(sidecar.isPicked)
        #expect(sidecar.keywords == ["Kyoto"])
        #expect(try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT creationDate, latitude, longitude FROM photo_metadata WHERE assetId = ?", arguments: [b])
        } == keptRow)
        #expect(SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent("B.JPG"))) == before)
        #expect(FileMerge.confirmation(marked: 1).contains("stars, flag and keywords"))
    }
}
