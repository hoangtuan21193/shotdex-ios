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

        let info = try await PhotoInfoQueries(database: database).info(photoId: "A")
        #expect(info.title == "Last light over Wakakusa")
        #expect(info.caption == "Deer crossing the lawn")
        #expect(info.keywords == ["Nara", "sunset"])
        #expect(info.fileName == "DSC04512.ARW")
        #expect(!info.isInPhotos)
        #expect(info.serverCopies == [.init(serverName: "NAS Home", path: "Shared/2025/DSC04512.ARW")])

        // Saves in the same second: the last one wins (typing).
        let now = Date()
        try store.setCaption("Deer", photoIds: ["A"], at: now)
        try store.setCaption("Deers", photoIds: ["A"], at: now)
        #expect(try await PhotoInfoQueries(database: database).info(photoId: "A").caption == "Deers")

        // An empty title clears it.
        try store.setTitle("  ", photoIds: ["A"], at: Date().addingTimeInterval(1))
        #expect(try await PhotoInfoQueries(database: database).info(photoId: "A").title == nil)
    }
}
