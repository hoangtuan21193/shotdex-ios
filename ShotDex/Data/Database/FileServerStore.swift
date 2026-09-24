import Foundation
import GRDB

/// Reads and writes the file servers the user set up (FS-15.01), and keeps
/// each one's Keychain password in step with its row.
struct FileServerStore: Sendable {
    let database: AppDatabase
    let passwords: any ServerPasswordStoring

    /// By name — the order the Settings list shows.
    func fetchAll() throws -> [FileServer] {
        try database.reader.read { db in
            try FileServer
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
        }
    }

    func fetch(id: String) throws -> FileServer? {
        try database.reader.read { db in try FileServer.fetchOne(db, key: id) }
    }

    /// The server the prepare step starts on: the last one uploaded to, else
    /// the first one added.
    func mostRecentlyUsed() throws -> FileServer? {
        try database.reader.read { db in
            try FileServer
                .order(Column("lastUsedAt").desc, Column("createdAt").asc)
                .fetchOne(db)
        }
    }

    func count() throws -> Int {
        try database.reader.read { db in try FileServer.fetchCount(db) }
    }

    /// Saves the row and, when given, the password. A nil password leaves the
    /// stored one alone — the form shows it masked and does not re-send it
    /// unless the user typed a new one.
    func save(_ server: FileServer, password: String?) throws {
        try database.writer.write { db in
            var row = server
            // A different host or port is a different machine: the key the
            // user trusted for the old one says nothing about it.
            if let existing = try FileServer.fetchOne(db, key: server.id),
               existing.host != server.host || existing.port != server.port {
                row.hostKeyFingerprint = nil
            }
            try row.upsert(db)
        }
        if let password {
            try passwords.setPassword(password, for: server.id)
        }
    }

    func setHostKeyFingerprint(_ fingerprint: String?, for serverId: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE file_servers SET hostKeyFingerprint = ? WHERE id = ?",
                arguments: [fingerprint, serverId]
            )
        }
    }

    func markUsed(_ serverId: String, at date: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE file_servers SET lastUsedAt = ? WHERE id = ?",
                arguments: [Int(date.timeIntervalSince1970), serverId]
            )
        }
    }

    /// Removes the server and its password. Its upload history stays — the
    /// foreign key nulls the id and the row keeps the name.
    func delete(id: String) throws {
        _ = try database.writer.write { db in
            try FileServer.deleteOne(db, key: id)
        }
        passwords.removePassword(for: id)
    }

    func password(for serverId: String) -> String? {
        passwords.password(for: serverId)
    }
}
