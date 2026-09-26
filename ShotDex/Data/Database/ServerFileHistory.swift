import Foundation
import GRDB

/// Keeps both histories true to the server after ShotDex renames or
/// deletes something there (FS-17.01 §4b). The upload history is the proof
/// that lets FS-15.02 §7 offer to delete photos from this device: a file
/// deleted on the server must stop counting, or a photo could be deleted
/// here with no copy left anywhere.
///
/// Rows of every connection that reaches the same files — same protocol,
/// host and port — are touched, since one server can be added many times.
/// Matching too much only ever takes proof away, which is the safe side.
struct ServerFileHistory: Sendable {
    let database: AppDatabase

    /// Drops the upload proof for `path` (and, for a folder, everything
    /// in it). Returns how many rows went. Download rows stay: they say
    /// where a library photo came from, which is still true.
    @discardableResult
    func forgetUploads(at path: String, on server: FileServer) throws -> Int {
        try database.writer.write { db in
            let ids = try Self.connectionIds(sameFilesAs: server, db)
            let rows = try Row.fetchAll(db, sql: "SELECT id, remotePath FROM server_uploads WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
            let doomed: [Int64] = rows.compactMap { row in
                ServerHistoryPaths.isAffected(row["remotePath"], by: path) ? row["id"] : nil
            }
            for id in doomed {
                try db.execute(sql: "DELETE FROM server_uploads WHERE id = ?", arguments: [id])
            }
            return doomed.count
        }
    }

    /// `path` became `newPath` on the server: both histories follow, so In
    /// Library marks and the upload proof keep matching.
    func move(_ path: String, to newPath: String, on server: FileServer) throws {
        try database.writer.write { db in
            let ids = try Self.connectionIds(sameFilesAs: server, db)
            for table in ["server_uploads", "server_downloads"] {
                let rows = try Row.fetchAll(db, sql: "SELECT id, remotePath FROM \(table) WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
                for row in rows {
                    guard let renamed = ServerHistoryPaths.renamed(row["remotePath"], from: path, to: newPath) else { continue }
                    try db.execute(sql: "UPDATE \(table) SET remotePath = ? WHERE id = ?", arguments: [renamed, row["id"] as Int64])
                }
            }
        }
    }

    private static func connectionIds(sameFilesAs server: FileServer, _ db: Database) throws -> [String] {
        let ids = try String.fetchAll(db, sql: """
            SELECT id FROM file_servers
            WHERE transferProtocol = ? AND lower(host) = lower(?) AND port = ?
            """, arguments: [server.transferProtocol.rawValue, server.host, server.port])
        return Array(Set(ids + [server.id]))
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
