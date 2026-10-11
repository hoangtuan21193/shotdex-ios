import Foundation
import GRDB

/// Albums ShotDex keeps itself (FS-19.05 §6): they hold photos from every
/// source, where a Photos album holds only Photos Library items. New Album
/// makes one as soon as the library has a source other than Photos.
struct ShotDexAlbumStore: Sendable {
    let database: AppDatabase

    /// Which kind New Album makes.
    enum NewAlbumKind: Equatable, Sendable {
        case photos
        case shotDex
    }

    func newAlbumKind() throws -> NewAlbumKind {
        try database.reader.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sources WHERE kind != 'photos')") == true ? .shotDex : .photos
        }
    }

    @discardableResult
    func create(name: String, at now: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try database.writer.write { db in
            let position = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM shotdex_albums") ?? -1) + 1
            try db.execute(sql: "INSERT INTO shotdex_albums (id, name, position, createdAt) VALUES (?, ?, ?, ?)",
                           arguments: [id, name, position, Int(now.timeIntervalSince1970)])
        }
        return id
    }

    func add(photoIds: [String], to albumId: String, at now: Date = Date()) throws {
        try database.writer.write { db in
            for id in photoIds {
                try db.execute(sql: "INSERT OR IGNORE INTO shotdex_album_members (albumId, photoId, addedAt) VALUES (?, ?, ?)",
                               arguments: [albumId, try PhotoAliasResolver.photoId(db, for: id), Int(now.timeIntervalSince1970)])
            }
        }
    }

    /// The album's photos the library shows — a hidden or offline-hidden
    /// photo stays a member but is not listed.
    func photoIds(in albumId: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT m.photoId FROM shotdex_album_members m JOIN photo_metadata ON photo_metadata.assetId = m.photoId
                WHERE m.albumId = ? AND \(PhotoVisibility.condition)
                ORDER BY m.addedAt, m.rowid
                """, arguments: [albumId])
        }
    }

    /// Photos among `photoIds` with no Photos copy: a Photos album cannot
    /// hold them, so its row in Add to Album is dimmed.
    func photosOnlyOutside(_ photoIds: [String]) throws -> [String] {
        guard !photoIds.isEmpty else { return [] }
        return try database.reader.read { db in
            let inPhotos = Set(try String.fetchAll(db, sql: """
                SELECT DISTINCT photoId FROM photo_copies
                WHERE kind = 'photos' AND missingSince IS NULL AND photoId IN (\(databaseQuestionMarks(count: photoIds.count)))
                """, arguments: StatementArguments(photoIds)))
            return photoIds.filter { !inPhotos.contains($0) }
        }
    }

    static let photosAlbumLimit = String(localized: "Photos albums can only hold Photos Library items.",
                                         comment: "Add to Album: why a Photos album row is dimmed for photos only in folders or on a server")
}
