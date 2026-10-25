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
