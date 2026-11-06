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

    /// One history row a move rewrote: which table, which row, its path
    /// before and after, and the change (`from`) that moved it — what an
    /// undo needs to put it back (FS-19.08 §6b).
    struct MovedRow: Equatable, Sendable {
        let table: String
        let rowId: String
        let pathBefore: String
        let pathAfter: String
        let sourcePath: String
    }

    /// Several moves in one write (a common-photos run, FS-19.08 §6): every
    /// history row is read once and each change applied in order. Returns
    /// the rows rewritten; `recording` stores them in the same write, so a
    /// quit never leaves the history moved with no record of it.
    @discardableResult
    func move(_ changes: [(from: String, to: String)], on server: FileServer,
              recording: ((Database, [MovedRow]) throws -> Void)? = nil) throws -> [MovedRow] {
        guard !changes.isEmpty else { return [] }
        func renamed(_ path: String) -> (path: String, source: String)? {
            var current = path
            var source: String?
            for change in changes {
                if let next = ServerHistoryPaths.renamed(current, from: change.from, to: change.to) {
                    current = next
                    source = source ?? change.from
                }
            }
            return source.map { (current, $0) }
        }
        return try database.writer.write { db in
            var moved: [MovedRow] = []
            let ids = try Self.connectionIds(sameFilesAs: server, db)
            let tiles = try Row.fetchAll(db, sql: "SELECT id, path FROM server_shortcuts WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
            for tile in tiles {
                let before: String = tile["path"]
                guard let (path, source) = renamed(before) else { continue }
                try db.execute(sql: "UPDATE OR IGNORE server_shortcuts SET path = ? WHERE id = ?", arguments: [path, tile["id"] as String])
                if db.changesCount > 0 {
                    moved.append(MovedRow(table: "server_shortcuts", rowId: tile["id"], pathBefore: before, pathAfter: path, sourcePath: source))
                }
            }
            for table in ["server_uploads", "server_downloads"] {
                let rows = try Row.fetchAll(db, sql: "SELECT id, remotePath FROM \(table) WHERE serverId IN (\(Self.placeholders(ids.count)))", arguments: StatementArguments(ids))
                for row in rows {
                    let before: String = row["remotePath"]
                    guard let (path, source) = renamed(before) else { continue }
                    let id: Int64 = row["id"]
                    try db.execute(sql: "UPDATE \(table) SET remotePath = ? WHERE id = ?", arguments: [path, id])
                    moved.append(MovedRow(table: table, rowId: String(id), pathBefore: before, pathAfter: path, sourcePath: source))
                }
            }
            // Backup's ledger too (FS-19.08 §6): the backed-up bytes now live
            // at the new path, and the on-server check seeds hashes from it.
            let ledger = try Row.fetchAll(db, sql: """
                SELECT l.id, l.remotePath FROM backup_ledger l JOIN backup_jobs j ON j.id = l.jobId
                WHERE l.remotePath IS NOT NULL AND j.connectionId IN (\(Self.placeholders(ids.count)))
                """, arguments: StatementArguments(ids))
            for row in ledger {
                let before: String = row["remotePath"]
                guard let (path, source) = renamed(before) else { continue }
                let id: Int64 = row["id"]
                try db.execute(sql: "UPDATE backup_ledger SET remotePath = ? WHERE id = ?", arguments: [path, id])
                moved.append(MovedRow(table: "backup_ledger", rowId: String(id), pathBefore: before, pathAfter: path, sourcePath: source))
            }
            try recording?(db, moved)
            return moved
        }
    }

    /// Puts rows a move rewrote back where they were (FS-19.08 §6b) — each
    /// only while it still holds the path the move gave it. Returns, per
    /// row, whether it is settled: put back, or no longer at that path (the
    /// user moved on). A shortcut whose old path another shortcut now holds
    /// is not settled, so its record stays for a later try.
    @discardableResult
    func restore(_ rows: [MovedRow]) throws -> [Bool] {
        guard !rows.isEmpty else { return [] }
        return try database.writer.write { db in
            try rows.map { row in
                guard ["server_shortcuts", "server_uploads", "server_downloads", "backup_ledger"].contains(row.table) else { return true }
                let column = row.table == "server_shortcuts" ? "path" : "remotePath"
                let id: DatabaseValueConvertible = row.table == "server_shortcuts" ? row.rowId : (Int64(row.rowId) ?? -1)
                try db.execute(sql: "UPDATE OR IGNORE \(row.table) SET \(column) = ? WHERE id = ? AND \(column) = ?",
                               arguments: [row.pathBefore, id, row.pathAfter])
                if db.changesCount > 0 { return true }
                let stillThere = try Bool.fetchOne(db, sql: "SELECT 1 FROM \(row.table) WHERE id = ? AND \(column) = ?",
                                                   arguments: [id, row.pathAfter]) ?? false
                return !stillThere
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
