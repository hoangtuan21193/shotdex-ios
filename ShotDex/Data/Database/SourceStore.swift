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

    /// Remove Source (FS-19.01b §2): its photos leave ShotDex unless another
    /// source holds a copy; a photo left with none becomes an orphan and
    /// keeps its stars, flags and recipe for 30 days. Nothing in the folder,
    /// on the drive or on the server is touched.
    func remove(sourceId: String, at now: Date = Date()) throws {
        guard sourceId != PhotoLibrarySource.id else { return }
        try database.writer.write { db in
            let copies = try String.fetchAll(db, sql: "SELECT id FROM photo_copies WHERE sourceId = ?", arguments: [sourceId])
            try FileCopyWriter.markMissing(db, copies, at: Int(now.timeIntervalSince1970))
            try db.execute(sql: "DELETE FROM pending_sidecar WHERE copyId IN (SELECT id FROM photo_copies WHERE sourceId = ?)", arguments: [sourceId])
            try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [sourceId])
        }
    }

    /// The server source of a connection, if it was added as one (FS-19.03 §1).
    func serverSourceId(connectionId: String) throws -> String? {
        try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM sources WHERE kind = 'server' AND connectionId = ?", arguments: [connectionId])
        }
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

    /// What a source row says beside its name (FS-19.03 §1, §6).
    enum Status: String, Sendable {
        case online
        case offline
        /// The server refused the saved password; the row offers Edit
        /// Connection… and nothing asks for the password again.
        case passwordRejected
    }

    func status(sourceId: String) throws -> Status {
        try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM sources WHERE id = ?", arguments: [sourceId])
        }.flatMap(Status.init(rawValue:)) ?? .online
    }

    /// A refused password: the photos stay as they are — online or not is
    /// unknown, nothing is missing.
    func setPasswordRejected(sourceId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET status = ? WHERE id = ?", arguments: [Status.passwordRejected.rawValue, sourceId])
        }
    }

    /// Photos the library shows with a copy in each source — the number on
    /// each Sources row. A photo in two sources counts in both.
    func photoCounts() throws -> [String: Int] {
        try database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: """
                SELECT c.sourceId, COUNT(DISTINCT c.photoId) AS n FROM photo_copies c
                JOIN photo_metadata ON photo_metadata.assetId = c.photoId
                WHERE c.missingSince IS NULL AND c.isHidden = 0 AND \(PhotoVisibility.condition)
                GROUP BY c.sourceId
                """).map { ($0["sourceId"] as String, $0["n"] as Int) })
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
