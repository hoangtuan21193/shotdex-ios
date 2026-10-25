import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §8: the grid's "on server" glyph shows what is on a server
/// source now, not what was uploaded once.
@MainActor
struct OnServerIndexTests {
    /// AC-87 (glyph): the photo is on `Shared/`; the script deletes the file
    /// and the listing marks it missing — the glyph goes. An upload in the
    /// history alone never draws it.
    @Test func glyphFollowsCopies() async throws {
        let f = try OnServerFixture(photos: 2)
        try f.photo(0, files: [("1:IMG_0.HEIC", .photo, 1_000, "a")])
        try f.photo(1, files: [("1:IMG_1.HEIC", .photo, 1_001, "b")])
        try f.server("Shared/2025/c.HEIC", size: 1_000, sha: "a")
        let index = ServerUploadIndex(store: ServerUploadStore(database: f.database))
        let presence = OnServerProgressQueries(database: f.database)
        index.reloadPresence { try presence.presentAnywhere() }
        while index.presentVersion == 0 { await Task.yield() }
        #expect(index.presentIds == ["P0"])

        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET missingSince = 1 WHERE kind = 'server'")
        }
        index.reloadPresence { try presence.presentAnywhere() }
        while index.presentVersion == 1 { await Task.yield() }
        #expect(index.presentIds.isEmpty)
        #expect(index.assetIds.isEmpty)
    }
}

extension OnServerIndexTests {
    /// AC-91: Photo Info lists the source and the path from the server's
    /// root — the connection's Folder first — for each matched file.
    @Test func photoInfoLocations() throws {
        let f = try OnServerFixture(photos: 1)
        try FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
            .save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                             folder: "iCloud Photo"), password: "pw")
        try f.photo(0, files: [("1:a.HEIC", .photo, 1_000, "a"), ("9:a.MOV", .pairedVideo, 2_000, "m")])
        try f.server("Shared/2025/a.HEIC", size: 1_000, sha: "a", companion: ("Shared/2025/a.MOV", 2_000, "m"))
        #expect(try OnServerProgressQueries(database: f.database).locations(photoId: "P0") == [
            OnServerLocation(sourceName: "NAS Home", path: "iCloud Photo/Shared/2025/a.HEIC"),
            OnServerLocation(sourceName: "NAS Home", path: "iCloud Photo/Shared/2025/a.MOV"),
        ])
        // Not all files there: no line.
        let g = try OnServerFixture(photos: 1)
        try g.photo(0, files: [("1:a.HEIC", .photo, 1_000, "a"), ("9:a.MOV", .pairedVideo, 2_000, "m")])
        try g.server("Shared/a.HEIC", size: 1_000, sha: "a")
        #expect(try OnServerProgressQueries(database: g.database).locations(photoId: "P0").isEmpty)
    }
}
