import Foundation
import GRDB

/// Reads and writes user-created smart albums (saved `FilterCriteria`).
struct SmartAlbumStore: Sendable {
    let database: AppDatabase

    /// All smart albums, newest first.
    func fetchAllOrdered() throws -> [SmartAlbum] {
        try database.reader.read { db in
            try SmartAlbum
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Inserts or updates a smart album (keyed by `id`).
    func upsert(_ album: SmartAlbum) throws {
        try database.writer.write { db in
            try album.upsert(db)
        }
    }

    func delete(id: String) throws {
        _ = try database.writer.write { db in
            try SmartAlbum.deleteOne(db, key: id)
        }
    }
}
