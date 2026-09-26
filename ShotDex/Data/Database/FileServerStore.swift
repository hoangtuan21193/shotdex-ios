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
    ///
    /// A name another connection already has gets ` (2)`, ` (3)`… — the ⋯
    /// menu lists names and nothing else (FS-15.01 §3).
    func save(_ server: FileServer, password: String?) throws {
        try database.writer.write { db in
            var row = server
            let others = try String.fetchAll(db, sql: "SELECT name FROM file_servers WHERE id != ?", arguments: [server.id])
            row.name = FileServerNaming.uniqueName(server.name, existing: others)
            if let existing = try FileServer.fetchOne(db, key: server.id) {
                // A different host or port is a different machine: the key
                // the user trusted for the old one says nothing about it.
                if existing.host != server.host || existing.port != server.port {
                    row.trustedFingerprint = nil
                }
                // The upload sheet owns these; the form only carries what it
                // read, which may be older than the last upload.
                row.uploadFolder = existing.uploadFolder
                row.usesDateFolders = existing.usesDateFolders
                // A new default folder in the form wins over the remembered one.
                if ServerUploadPath.normalizedFolder(existing.folder) != ServerUploadPath.normalizedFolder(server.folder) {
                    row.uploadFolder = nil
                }
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
                sql: "UPDATE file_servers SET trustedFingerprint = ? WHERE id = ?",
                arguments: [fingerprint, serverId]
            )
        }
    }

    /// An upload started: this connection is the most recent, and its next
    /// upload starts in the same folder with the same Date Folders setting.
    func markUsed(_ serverId: String, folder: String, usesDateFolders: Bool, at date: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE file_servers SET lastUsedAt = ?, uploadFolder = ?, usesDateFolders = ? WHERE id = ?",
                arguments: [Int(date.timeIntervalSince1970), ServerUploadPath.normalizedFolder(folder), usesDateFolders, serverId]
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
