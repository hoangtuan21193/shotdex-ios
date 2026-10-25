import Foundation
import GRDB

/// How far the on-server check has come for one Source condition
/// (FS-19.07 §7): the line under a smart album's conditions.
struct OnServerProgress: Equatable, Sendable {
    /// Photos items whose answer is known — in **is** or **is not**.
    var checked = 0
    /// Every Photos item in the library.
    var total = 0
    /// What is left to download from Photos to finish, by the files' sizes.
    var bytesToDownload: Int64 = 0
    /// Items not there only because their edit render is not
    /// (`Edited — edit not on NAS Home`).
    var editedOnlyMissing = 0
}

struct OnServerProgressQueries: Sendable {
    let database: AppDatabase

    func progress(sourceId: String, folder: String?) throws -> OnServerProgress {
        let (present, presentValues) = OnServerPresenceSQL.present(sourceId: sourceId, folder: folder)
        let (missing, missingValues) = OnServerPresenceSQL.missing(sourceId: sourceId, folder: folder)
        let (open, openValues) = OnServerPresenceSQL.unsettled(file: "f", sourceId: sourceId, folder: folder)
        let (match, matchValues) = OnServerPresenceSQL.matched(file: "f", sourceId: sourceId, folder: folder)
        let visible = PhotoVisibility.condition
        let roles = OnServerPresenceSQL.roles
        let edited = OnServerPresenceSQL.editedRoles
        return try database.reader.read { db in
            var out = OnServerProgress()
            out.total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM photo_metadata
                WHERE assetId IN (SELECT photoId FROM photo_copies WHERE kind = 'photos') AND \(visible)
                """) ?? 0
            out.checked = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata WHERE (\(present) OR \(missing)) AND \(visible)",
                                           arguments: StatementArguments(presentValues + missingValues)) ?? 0
            out.bytesToDownload = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(f.size), 0) FROM copy_files f JOIN photo_copies pc ON pc.id = f.copyId AND pc.kind = 'photos'
                WHERE f.sha256 IS NULL AND f.role IN \(roles) AND \(open)
                """, arguments: StatementArguments(openValues)) ?? 0
            out.editedOnlyMissing = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM photo_metadata WHERE \(missing) AND \(visible) AND assetId IN (
                    SELECT pc.photoId FROM photo_copies pc WHERE pc.kind = 'photos'
                      AND EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(edited) AND NOT \(match))
                      AND NOT EXISTS (SELECT 1 FROM copy_files f WHERE f.copyId = pc.id AND f.role IN \(roles)
                                      AND f.role NOT IN \(edited) AND NOT \(match)))
                """, arguments: StatementArguments(missingValues + matchValues + matchValues)) ?? 0
            return out
        }
    }
}
