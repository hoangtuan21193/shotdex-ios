import Foundation
import GRDB

/// Collections → Network tiles (FS-17.04). Nothing here touches the server.
struct ServerShortcutStore: Sendable {
    let database: AppDatabase

    /// Oldest first: a new tile goes at the end of the row.
    func fetchAll() throws -> [ServerShortcut] {
        try database.reader.read { db in
            try ServerShortcut.order(Column("createdAt"), Column("rowid")).fetchAll(db)
        }
    }

    func shortcut(serverId: String, path: String) throws -> ServerShortcut? {
        try database.reader.read { db in
            try ServerShortcut
                .filter(Column("serverId") == serverId && Column("path") == ServerUploadPath.normalizedFolder(path))
                .fetchOne(db)
        }
    }

    /// Adds the folder, or returns the tile it already has.
    @discardableResult
    func add(serverId: String, path: String, name: String) throws -> ServerShortcut {
        try database.writer.write { db in
            let normalized = ServerUploadPath.normalizedFolder(path)
            if let existing = try ServerShortcut
                .filter(Column("serverId") == serverId && Column("path") == normalized)
                .fetchOne(db) {
                return existing
            }
            let row = ServerShortcut(serverId: serverId, path: normalized, name: name)
            try row.insert(db)
            return row
        }
    }

    func rename(_ id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE server_shortcuts SET name = ? WHERE id = ?", arguments: [trimmed, id])
        }
    }

    func remove(_ id: String) throws {
        try database.writer.write { db in
            _ = try ServerShortcut.deleteOne(db, key: id)
        }
    }

    func setCover(_ jpeg: Data?, for id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE server_shortcuts SET coverJPEG = ? WHERE id = ?", arguments: [jpeg, id])
        }
    }
}
