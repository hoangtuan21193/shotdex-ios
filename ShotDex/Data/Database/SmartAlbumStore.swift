import Foundation
import GRDB

/// Reads and writes user-created smart albums (saved `FilterCriteria`).
struct SmartAlbumStore: Sendable {
    let database: AppDatabase

    /// All smart albums, newest first. A `Source is <server>` condition comes
    /// back as Also on Server (FS-19.07 §7).
    func fetchAllOrdered() throws -> [SmartAlbum] {
        try database.reader.read { db in
            let serverIds = try Set(String.fetchAll(db, sql: "SELECT id FROM sources WHERE kind = 'server'"))
            return try SmartAlbum
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map { album in
                    var album = album
                    album.query = AlsoOnServerMigration.rewrite(album.query, serverIds: serverIds)
                    return album
                }
        }
    }

    /// Inserts or updates a smart album (keyed by `id`).
    func upsert(_ album: SmartAlbum) throws {
        try database.writer.write { db in
            try album.upsert(db)
        }
    }

    /// `upsert` without holding the caller's thread while the writer is busy
    /// (an index batch): for a click on the main actor.
    func save(_ album: SmartAlbum) async throws {
        try await database.writer.write { db in
            try album.upsert(db)
        }
    }

    /// Deletes the smart album and its Keep in Photos link; the album in
    /// Photos stays (FS-06.12 §4).
    func delete(id: String) throws {
        _ = try database.writer.write { db in
            try SmartAlbumPhotosAlbum.deleteOne(db, key: id)
            return try SmartAlbum.deleteOne(db, key: id)
        }
    }
}
