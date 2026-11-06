import Foundation
import GRDB

/// Reads `CopyReachability` for one photo from its copies.
struct CopyReachabilityQueries: Sendable {
    let database: AppDatabase

    /// Photos with no copy that can be opened now — every one is on a drive
    /// or server not connected (FS-19.01b §2): the grid's offline glyph.
    func offlinePhotoIds() async throws -> Set<String> {
        try await database.reader.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT DISTINCT c.photoId FROM photo_copies c
                WHERE c.missingSince IS NULL AND c.isHidden = 0 AND c.kind != 'photos' AND c.isOnline = 0
                  AND NOT EXISTS (SELECT 1 FROM photo_copies o WHERE o.photoId = c.photoId AND o.missingSince IS NULL
                                  AND o.isHidden = 0 AND (o.kind = 'photos' OR o.isOnline = 1))
                """))
        }
    }

    /// Up to `limit` file paths a source knows, for checking that a folder
    /// picked with Locate… is that source (FS-19.01b §2).
    func knownPaths(sourceId: String, limit: Int = 50) async throws -> [String] {
        try await database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT relativePath FROM photo_copies
                WHERE sourceId = ? AND relativePath IS NOT NULL AND missingSince IS NULL LIMIT ?
                """, arguments: [sourceId, limit])
        }
    }

    func reachability(photoId: String) throws -> CopyReachability {
        try database.reader.read { db in
            let reachable = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM photo_copies WHERE photoId = ? AND missingSince IS NULL AND isHidden = 0
                              AND (kind = 'photos' OR isOnline = 1))
                """, arguments: [photoId]) ?? false
            if reachable { return .available }
            guard let row = try Row.fetchOne(db, sql: """
                SELECT s.name, s.kind FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.missingSince IS NULL ORDER BY s.createdAt, s.id LIMIT 1
                """, arguments: [photoId]) else { return .available }
            return .offline(sourceName: row["name"], isServer: (row["kind"] as String) == "server")
        }
    }
}
