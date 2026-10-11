import Foundation
import GRDB

/// Reads `CopyReachability` for one photo from its copies.
struct CopyReachabilityQueries: Sendable {
    let database: AppDatabase

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
