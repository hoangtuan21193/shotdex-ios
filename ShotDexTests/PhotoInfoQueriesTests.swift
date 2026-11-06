import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.02 §8: one photo's Get Info.
struct PhotoInfoQueriesTests {
    @Test func aFolderPhotoOnAServerToo() async throws {
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let t7 = try sources.addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('A', 1)")
            for (id, source, kind, path) in [("A-t7", t7, "file", "RAW/DSC04512.ARW"), ("A-nas", nas, "server", "Shared/2025/DSC04512.ARW")] {
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES (?, 'A', ?, ?, ?, ?)",
                               arguments: [id, source, kind, path, path.lowercased()])
            }
            try PhotoUserMarksStore.addKeywords(db, ["Nara", "sunset"], photoId: "A", at: 1)
        }
        let store = PhotoUserMarksStore(database: database)
        try store.setTitle("Last light over Wakakusa", photoIds: ["A"])
        try store.setCaption("Deer crossing the lawn", photoIds: ["A"])
        try store.setCreator("Linh Pham", photoIds: ["A"])
        try store.setCopyright("© 2026 Linh Pham Photography", photoIds: ["A"])

        let info = try await PhotoInfoQueries(database: database).info(photoId: "A")
        #expect(info.title == "Last light over Wakakusa")
        #expect(info.caption == "Deer crossing the lawn")
        #expect(info.creator == "Linh Pham")
        #expect(info.copyright == "© 2026 Linh Pham Photography")
        #expect(info.filePath == "RAW/DSC04512.ARW")
        #expect(info.keywords == ["Nara", "sunset"])
        #expect(info.fileName == "DSC04512.ARW")
        #expect(!info.isInPhotos)
        #expect(info.serverCopies == [.init(serverName: "NAS Home", path: "Shared/2025/DSC04512.ARW")])

        // A selection reads in one go; an id not in the index still has an entry.
        let several = try await PhotoInfoQueries(database: database).infos(photoIds: ["A", "missing"])
        #expect(several["A"]?.title == "Last light over Wakakusa")
        #expect(several["missing"] != nil)
        #expect(several["missing"]?.metadata == nil)
        #expect(several["missing"]?.isInPhotos == false)

        // Saves in the same second: the last one wins (typing).
        let now = Date()
        try store.setCaption("Deer", photoIds: ["A"], at: now)
        try store.setCaption("Deers", photoIds: ["A"], at: now)
        #expect(try await PhotoInfoQueries(database: database).info(photoId: "A").caption == "Deers")

        // An empty title clears it.
        try store.setTitle("  ", photoIds: ["A"], at: Date().addingTimeInterval(1))
        #expect(try await PhotoInfoQueries(database: database).info(photoId: "A").title == nil)
    }

    /// Creator and Copyright go to the sidecar as dc:creator and dc:rights.
    @Test func creatorAndCopyrightReachTheSidecarPatch() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = PhotoUserMarksStore(database: database)
        try store.setCreator("Linh Pham", photoIds: ["A"])
        try store.setCopyright("© 2026 Linh Pham", photoIds: ["A"])
        let patch = try await database.reader.read { db in try SidecarWriter.patch(db, photoId: "A") }
        #expect(patch.creator == .set("Linh Pham"))
        #expect(patch.rights == .set("© 2026 Linh Pham"))
        let xmp = XMPPatcher.apply(patch, to: nil)
        #expect(xmp.contains("Linh Pham"))
        #expect(xmp.contains("© 2026 Linh Pham"))

        // Cleared: the sidecar's goes too.
        try store.setCreator("", photoIds: ["A"], at: Date().addingTimeInterval(1))
        let cleared = try await database.reader.read { db in try SidecarWriter.patch(db, photoId: "A") }
        #expect(cleared.creator == .remove)
        #expect(cleared.rights == .set("© 2026 Linh Pham"))
    }
}
