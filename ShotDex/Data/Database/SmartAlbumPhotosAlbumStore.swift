import Foundation
import GRDB

/// Where a Keep in Photos album stands — what the line under the smart album
/// says (FS-06.12 §3).
enum PhotosAlbumSyncState: String, Codable, Sendable {
    case idle
    case updating
    case synced
    /// The album was deleted in Photos; the switch went off.
    case deletedInPhotos
    /// A PhotoKit write failed; the next pass tries again.
    case failed
    /// Photos access is not Full: nothing is written until it is.
    case needsFullAccess
}

/// One smart album's Keep in Photos link (FS-06.12 §5).
struct SmartAlbumPhotosAlbum: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "smart_album_photos_album"

    var smartAlbumId: String
    var collectionLocalId: String?
    var isEnabled: Bool
    var lastSyncedAt: Int?
    var assetCount: Int
    var state: PhotosAlbumSyncState
}

/// Reads and writes the Keep in Photos links, and the Photos items a smart
/// album keeps there.
struct SmartAlbumPhotosAlbumStore: Sendable {
    let database: AppDatabase

    func link(_ smartAlbumId: String) throws -> SmartAlbumPhotosAlbum? {
        try database.reader.read { db in try SmartAlbumPhotosAlbum.fetchOne(db, key: smartAlbumId) }
    }

    func links() throws -> [SmartAlbumPhotosAlbum] {
        try database.reader.read { db in try SmartAlbumPhotosAlbum.fetchAll(db) }
    }

    func save(_ link: SmartAlbumPhotosAlbum) throws {
        try database.writer.write { db in try link.upsert(db) }
    }

    /// What a sync pass writes back: only its own columns, and only while the
    /// link is still on — a switch turned off or an album deleted mid-pass
    /// stays that way (review 2026-11-07). False when the link is off or gone.
    @discardableResult
    func recordSync(_ link: SmartAlbumPhotosAlbum) throws -> Bool {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE smart_album_photos_album
                SET collectionLocalId = ?, state = ?, lastSyncedAt = ?, assetCount = ?, isEnabled = ?
                WHERE smartAlbumId = ? AND isEnabled = 1
                """, arguments: [link.collectionLocalId, link.state.rawValue, link.lastSyncedAt, link.assetCount,
                                 link.isEnabled, link.smartAlbumId])
            return db.changesCount > 0
        }
    }

    func isEnabled(_ smartAlbumId: String) throws -> Bool {
        try database.reader.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM smart_album_photos_album WHERE smartAlbumId = ?",
                              arguments: [smartAlbumId]) ?? false
        }
    }

    /// Turns Keep in Photos on or off. Off keeps the album's id so turning it
    /// back on reuses the album (FS-06.12 §4).
    func setEnabled(_ enabled: Bool, smartAlbumId: String) throws {
        try database.writer.write { db in
            var link = try SmartAlbumPhotosAlbum.fetchOne(db, key: smartAlbumId)
                ?? SmartAlbumPhotosAlbum(smartAlbumId: smartAlbumId, collectionLocalId: nil, isEnabled: enabled,
                                         lastSyncedAt: nil, assetCount: 0, state: .idle)
            // Turned on again: the album is reused if it is still there and
            // made anew if not — not taken for "deleted while kept".
            if enabled, !link.isEnabled {
                link.lastSyncedAt = nil
                link.state = .idle
            }
            link.isEnabled = enabled
            try link.upsert(db)
        }
    }

    /// The PhotoKit ids of the smart album's Photos items, newest first: what
    /// the album in Photos must hold. Items that live only in a folder or on
    /// a server have no PHAsset and are left out (FS-06.12 §4).
    func photoKitIds(matching query: SmartAlbumQuery) throws -> [String] {
        // Never the whole library: no condition, or one that compiles to
        // nothing (a term that folds to empty), would widen the album to
        // every photo (review 2026-11-07).
        let rules = query.validRules + query.validGroups.flatMap(\.rules)
        guard !rules.isEmpty, rules.allSatisfy({ SmartAlbumSQLBuilder.clause(for: $0) != nil }) else { return [] }
        let (whereSQL, arguments) = SmartAlbumSQLBuilder.whereClause(for: query)
        return try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT pc.photoKitId FROM photo_copies pc
                JOIN photo_metadata m ON m.assetId = pc.photoId
                WHERE pc.kind = 'photos' AND pc.missingSince IS NULL AND pc.photoKitId IS NOT NULL
                  AND pc.photoId IN (SELECT assetId FROM photo_metadata \(whereSQL))
                ORDER BY m.creationDate DESC
                """, arguments: arguments)
        }
    }
}
