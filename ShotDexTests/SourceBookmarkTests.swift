import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.01b §2 — folder access that goes and comes back.
@MainActor
@Suite struct SourceBookmarkTests {
    /// AC-13, AC-14: "Client Shoots 2026" (5 photos, 2 with ★) loses its
    /// bookmark — it no longer opens. The source says Needs access; the 5
    /// photos stay in the library, offline. Grant Access… on the folder (now
    /// "Clients 2026") keeps the same 5 ids, the stars, and adds no photo.
    @Test func staleBookmarkKeepsPhotosThenRegrantRematches() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Grant-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = base.appendingPathComponent("Client Shoots 2026")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for n in 0..<5 {
            var options = MetadataFixture.Options()
            options.width += n * 8
            try MetadataFixture.encode(.jpeg, options: options).write(to: folder.appendingPathComponent("C\(n).JPG"))
        }
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "Client Shoots 2026", bookmark: try folder.bookmarkData(),
                                                                     includesSubfolders: true, pairsRawAndJpeg: true)
        let access = FolderSourceAccess(database: database)
        guard case .available(let opened) = try access.open(sourceId: sourceId) else { Issue.record("did not open"); return }
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        _ = try indexer.index(sourceId: sourceId, root: opened, includesSubfolders: true, pairsRawAndJpeg: true)
        let ids = try database.reader.read { db in try Set(String.fetchAll(db, sql: "SELECT id FROM photos")) }
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) SELECT photoId, 3, 1 FROM photo_copies WHERE relativePath IN ('C0.JPG', 'C1.JPG')")
            try db.execute(sql: "UPDATE sources SET bookmark = x'00' WHERE id = ?", arguments: [sourceId])
        }

        let renamed = base.appendingPathComponent("Clients 2026")
        try FileManager.default.moveItem(at: folder, to: renamed)
        #expect(try access.open(sourceId: sourceId) == .needsAccess)
        let library = LibraryQueries(database: database)
        #expect(try library.count(matching: FilterCriteria()) == 5)
        let offline = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE isOnline = 0") }
        #expect(offline == 5)

        try access.grant(sourceId: sourceId, folder: renamed)
        guard case .available(let granted) = try access.open(sourceId: sourceId) else { Issue.record("grant did not open"); return }
        let again = try indexer.index(sourceId: sourceId, root: granted, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(again.photos == 0)
        let after = try database.reader.read { db in
            (ids: try Set(String.fetchAll(db, sql: "SELECT id FROM photos")),
             stars: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_user_marks WHERE rating = 3") ?? 0,
             name: try String.fetchOne(db, sql: "SELECT name FROM sources WHERE id = ?", arguments: [sourceId]))
        }
        #expect(after.ids == ids)
        #expect(after.stars == 2)
        #expect(after.name == "Clients 2026")
        #expect(try library.count(matching: FilterCriteria()) == 5)
    }
}
