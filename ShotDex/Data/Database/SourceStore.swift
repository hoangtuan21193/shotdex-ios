import Foundation
import GRDB

/// Photo sources the user added (FS-19.01 §1); the Photos library is the
/// built-in row `photos-library`.
struct SourceStore: Sendable {
    let database: AppDatabase

    struct Source: Equatable, Sendable {
        let id: String
        let kind: String
        let name: String
        let bookmark: Data?
        let includesSubfolders: Bool
        let pairsRawAndJpeg: Bool
    }

    /// A folder or drive source; returns its id.
    @discardableResult
    func addFolder(name: String, bookmark: Data, includesSubfolders: Bool, pairsRawAndJpeg: Bool,
                   kind: String = "folder", at now: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO sources (id, kind, name, bookmark, subfolder, pairsRawAndJpeg, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, kind, name, bookmark, includesSubfolders ? "all" : "top", pairsRawAndJpeg, Int(now.timeIntervalSince1970)])
        }
        return id
    }

    /// A server connection added as a source (FS-19.03 §1): its Folder is
    /// what gets indexed; returns the source id.
    @discardableResult
    func addServer(name: String, connectionId: String, pairsRawAndJpeg: Bool = true, at now: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO sources (id, kind, name, connectionId, subfolder, pairsRawAndJpeg, createdAt)
                VALUES (?, 'server', ?, ?, 'all', ?, ?)
                """, arguments: [id, name, connectionId, pairsRawAndJpeg, Int(now.timeIntervalSince1970)])
        }
        return id
    }

    /// Include Subfolders, changed in Settings › Sources (FS-19.01 §2). The
    /// next read only opens files it has not seen: the rest are matched by
    /// path, size and date.
    func setIncludesSubfolders(_ on: Bool, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET subfolder = ? WHERE id = ?", arguments: [on ? "all" : "top", sourceId])
        }
    }

    /// When a Drive Is Disconnected (FS-19.01 §1): keep its photos in the
    /// library (offline) or hide them until it is back.
    enum WhenUnplugged: String, Sendable {
        case keepPhotos
        case hidePhotos
    }

    func setWhenUnplugged(_ choice: WhenUnplugged, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET whenUnplugged = ? WHERE id = ?", arguments: [choice.rawValue, sourceId])
        }
    }

    /// A drive unplugged or plugged back (FS-19.01b §1). Its copies follow
    /// the source: offline, not missing — an unplugged drive never makes an
    /// orphan, and nothing about its photos is forgotten.
    func setOnline(_ online: Bool, sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET status = ? WHERE id = ?", arguments: [online ? "online" : "offline", sourceId])
            try db.execute(sql: "UPDATE photo_copies SET isOnline = ? WHERE sourceId = ?", arguments: [online, sourceId])
        }
    }

    func sources() throws -> [Source] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sources ORDER BY createdAt, id").map {
                Source(id: $0["id"], kind: $0["kind"], name: $0["name"], bookmark: $0["bookmark"],
                       includesSubfolders: ($0["subfolder"] as String?) != "top", pairsRawAndJpeg: $0["pairsRawAndJpeg"])
            }
        }
    }
}
