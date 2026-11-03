import Foundation
import GRDB

/// Keeps both histories — and the Network tiles — true to the server after
/// ShotDex renames or deletes something there (FS-17.01 §4b, FS-17.04 §5). The upload history is the proof
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
            // A Network tile on the deleted folder, or inside it, goes too
            // (FS-17.04 §5).
            let tiles = try Row.fetchAll(db, sql: "SELECT id, path FROM server_shortcuts WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
            for tile in tiles where ServerHistoryPaths.isAffected(tile["path"], by: path) {
                try db.execute(sql: "DELETE FROM server_shortcuts WHERE id = ?", arguments: [tile["id"] as String])
            }
            return doomed.count
        }
    }

    /// `path` became `newPath` on the server: both histories follow, so In
    /// Library marks and the upload proof keep matching.
    func move(_ path: String, to newPath: String, on server: FileServer) throws {
        try move([(from: path, to: newPath)], on: server)
    }

    /// Several moves in one write (a common-photos run, FS-19.08 §6): every
    /// history row is read once and each change applied in order.
    func move(_ changes: [(from: String, to: String)], on server: FileServer) throws {
        guard !changes.isEmpty else { return }
        func renamed(_ path: String) -> String? {
            var current = path
            var changed = false
            for change in changes {
                if let next = ServerHistoryPaths.renamed(current, from: change.from, to: change.to) {
                    current = next
                    changed = true
                }
            }
            return changed ? current : nil
        }
        try database.writer.write { db in
            let ids = try Self.connectionIds(sameFilesAs: server, db)
            let tiles = try Row.fetchAll(db, sql: "SELECT id, path FROM server_shortcuts WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
            for tile in tiles {
                guard let path = renamed(tile["path"]) else { continue }
                try db.execute(sql: "UPDATE OR IGNORE server_shortcuts SET path = ? WHERE id = ?", arguments: [path, tile["id"] as String])
            }
            for table in ["server_uploads", "server_downloads"] {
                let rows = try Row.fetchAll(db, sql: "SELECT id, remotePath FROM \(table) WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
                for row in rows {
                    guard let path = renamed(row["remotePath"]) else { continue }
                    try db.execute(sql: "UPDATE \(table) SET remotePath = ? WHERE id = ?", arguments: [path, row["id"] as Int64])
                }
            }
            // Backup's ledger too (FS-19.08 §6): the backed-up bytes now live
            // at the new path, and the on-server check seeds hashes from it.
            let ledger = try Row.fetchAll(db, sql: """
                SELECT l.id, l.remotePath FROM backup_ledger l JOIN backup_jobs j ON j.id = l.jobId
                WHERE l.remotePath IS NOT NULL AND j.connectionId IN (\(Self.placeholders(ids.count)))
                """, arguments: StatementArguments(ids))
            for row in ledger {
                guard let path = renamed(row["remotePath"]) else { continue }
                try db.execute(sql: "UPDATE backup_ledger SET remotePath = ? WHERE id = ?", arguments: [path, row["id"] as Int64])
            }
        }
    }

    private static func connectionIds(sameFilesAs server: FileServer, _ db: Database) throws -> [String] {
        // Files folders have no host: each bookmark is its own place.
        guard server.transferProtocol.isNetwork else { return [server.id] }
        let candidates = try FileServer
            .filter(Column("transferProtocol") == server.transferProtocol.rawValue)
            .fetchAll(db)
        return Array(Set(candidates.filter { ServerIdentity.sameFiles($0, server) }.map(\.id) + [server.id]))
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
