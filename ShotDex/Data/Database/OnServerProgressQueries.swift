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

extension OnServerProgressQueries {
    /// Photos items on at least one server source (FS-19.07 §8) — the grid's
    /// "on server" glyph.
    func presentAnywhere() throws -> Set<String> {
        let sources = try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM sources WHERE kind = 'server'")
        }
        guard !sources.isEmpty else { return [] }
        let parts = sources.map { OnServerPresenceSQL.present(sourceId: $0, folder: nil) }
        let sql = "SELECT assetId FROM photo_metadata WHERE " + parts.map { "(\($0.sql))" }.joined(separator: " OR ")
        return try database.reader.read { db in
            Set(try String.fetchAll(db, sql: sql, arguments: StatementArguments(parts.flatMap(\.values))))
        }
    }
}

/// One server file a Photos item matched, for Photo Info (FS-19.07 §8).
struct OnServerLocation: Hashable, Sendable {
    var sourceName: String
    /// From the server's root: the connection's Folder, then the path.
    var path: String
}

extension OnServerProgressQueries {
    /// Where the photo's files are, on each server source it is on now —
    /// one line per matched file.
    func locations(photoId: String) throws -> [OnServerLocation] {
        let sources = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.id, s.name, COALESCE(fs.folder, '') AS root FROM sources s
                LEFT JOIN file_servers fs ON fs.id = s.connectionId
                WHERE s.kind = 'server' ORDER BY s.createdAt, s.id
                """).map { (id: $0["id"] as String, name: $0["name"] as String, root: $0["root"] as String) }
        }
        var out: [OnServerLocation] = []
        for source in sources {
            let (present, values) = OnServerPresenceSQL.present(sourceId: source.id, folder: nil)
            let paths = try database.reader.read { db -> [String] in
                guard try Bool.fetchOne(db, sql: "SELECT 1 FROM photo_metadata WHERE assetId = ? AND \(present)",
                                        arguments: StatementArguments([photoId] + values)) == true else { return [] }
                return try String.fetchAll(db, sql: """
                    SELECT DISTINCT CASE sf.fileKey WHEN 'companion' THEN sc.pairedPath ELSE sc.relativePath END AS path
                    FROM photo_copies pc
                    JOIN copy_files f ON f.copyId = pc.id AND f.role IN \(OnServerPresenceSQL.roles) AND f.sha256 IS NOT NULL
                    JOIN copy_files sf ON sf.sha256 = f.sha256
                    JOIN photo_copies sc ON sc.id = sf.copyId AND sc.kind = 'server' AND sc.missingSince IS NULL AND sc.sourceId = ?
                    WHERE pc.kind = 'photos' AND pc.photoId = ?
                    ORDER BY path
                    """, arguments: [source.id, photoId]).compactMap { $0 }
            }
            out += paths.map { OnServerLocation(sourceName: source.name, path: ServerUploadPath.join(source.root, $0)) }
        }
        return out
    }
}
