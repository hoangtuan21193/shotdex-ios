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

    // MARK: Rename / Duplicate (FS-06.08 §3c D5)

    enum NameError: LocalizedError, Equatable {
        case empty
        case taken(String)

        var errorDescription: String? {
            switch self {
            case .empty: String(localized: "A smart album needs a name.", comment: "Rename smart album: empty name")
            case .taken(let name): String(localized: "A smart album named “\(name)” already exists.", comment: "Rename smart album: the name is used")
            }
        }
    }

    func fetch(id: String) throws -> SmartAlbum? {
        try database.reader.read { db in try SmartAlbum.fetchOne(db, key: id) }
    }

    /// Renames, refusing an empty name or one another smart album already has
    /// (case-insensitive, as the editor's check). Returns the renamed album.
    @discardableResult
    func rename(id: String, to newName: String) throws -> SmartAlbum? {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NameError.empty }
        return try database.writer.write { db in
            guard var album = try SmartAlbum.fetchOne(db, key: id) else { return nil }
            let others = try SmartAlbum.fetchAll(db).filter { $0.id != id }
            if others.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased() }) {
                throw NameError.taken(name)
            }
            album.name = name
            try album.update(db)
            return album
        }
    }

    /// A copy named "<name> copy" ("… copy 2", …), same conditions and
    /// groups, Keep in Photos **off** — written with its link in one
    /// transaction so the default-on pass never sees it without one.
    @discardableResult
    func duplicate(id: String, now: Date = Date()) throws -> SmartAlbum? {
        try database.writer.write { db in
            guard let source = try SmartAlbum.fetchOne(db, key: id) else { return nil }
            let taken = Set(try SmartAlbum.fetchAll(db).map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            let copy = SmartAlbum(
                id: UUID().uuidString,
                name: Self.copyName(of: source.name, taken: taken),
                query: source.query,
                createdAt: Int(now.timeIntervalSince1970)
            )
            try copy.insert(db)
            try db.execute(sql: """
                INSERT OR REPLACE INTO smart_album_photos_album (smartAlbumId, isEnabled, assetCount, state)
                VALUES (?, 0, 0, 'idle')
                """, arguments: [copy.id])
            return copy
        }
    }

    /// "Night copy", then "Night copy 2", "Night copy 3"… — the first not in
    /// `taken` (lowercased names).
    static func copyName(of name: String, taken: Set<String>) -> String {
        let base = String(localized: "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) copy",
                          comment: "Duplicated smart album name, e.g. Night copy")
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
