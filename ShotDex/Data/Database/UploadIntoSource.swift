import Foundation
import GRDB

/// FS-19.03 §8: a file verified on a server inside the Folder of a server
/// source is a copy of its photo at once — its bytes are known, so it does
/// not wait for the next listing compare. The photo count does not change,
/// and Free Up Space then leaves the photo in ShotDex through that copy.
enum UploadIntoSource {
    static func record(_ db: Database, _ upload: ServerUploadRecord) throws {
        guard let serverId = upload.serverId,
              let folder = try String.fetchOne(db, sql: "SELECT folder FROM file_servers WHERE id = ?", arguments: [serverId]),
              let relativePath = relativePath(of: upload.remotePath, in: folder) else { return }
        for sourceId in try String.fetchAll(db, sql: "SELECT id FROM sources WHERE kind = 'server' AND connectionId = ?", arguments: [serverId]) {
            try record(db, upload, relativePath: relativePath, sourceId: sourceId)
        }
    }

    /// `remotePath` relative to the source's Folder; nil when it lies outside.
    static func relativePath(of remotePath: String, in folder: String) -> String? {
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if folder.isEmpty { return path }
        guard path.hasPrefix(folder + "/") else { return nil }
        return String(path.dropFirst(folder.count + 1))
    }

    private static func record(_ db: Database, _ upload: ServerUploadRecord, relativePath: String, sourceId: String) throws {
        let photoId = try PhotoAliasResolver.photoId(db, for: upload.assetId)
        let now = upload.uploadedAt
        let directory = (relativePath as NSString).deletingLastPathComponent
        // The other file of a RAW + JPEG asset, uploaded just before: one
        // copy, the RAW its original, as a listing would pair them.
        if let twin = try Row.fetchOne(db, sql: """
            SELECT id, relativePath FROM photo_copies
            WHERE sourceId = ? AND photoId = ? AND kind = 'server' AND missingSince IS NULL AND relativePathKey != ?
            """, arguments: [sourceId, photoId, FolderSourceIndexer.pathKey(relativePath)]),
           let twinPath: String = twin["relativePath"], (twinPath as NSString).deletingLastPathComponent == directory {
            if PairingRule.isRaw((relativePath as NSString).lastPathComponent) && !PairingRule.isRaw((twinPath as NSString).lastPathComponent) {
                try db.execute(sql: """
                    UPDATE photo_copies SET relativePath = ?, relativePathKey = ?, size = ?, modifiedAt = NULL, pairedPath = ? WHERE id = ?
                    """, arguments: [relativePath, FolderSourceIndexer.pathKey(relativePath), upload.byteCount, twinPath, twin["id"] as String])
            } else {
                try db.execute(sql: "UPDATE photo_copies SET pairedPath = ? WHERE id = ?", arguments: [relativePath, twin["id"] as String])
            }
            return
        }
        // No write date yet: the next compare reads the file once and keeps
        // it as this copy, matched by path.
        try db.execute(sql: """
            INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, isOnline, lastSeenAt)
            VALUES (?, ?, ?, 'server', ?, ?, ?, 1, ?)
            ON CONFLICT(sourceId, relativePathKey) WHERE relativePathKey IS NOT NULL
            DO UPDATE SET photoId = excluded.photoId, size = excluded.size, modifiedAt = NULL, missingSince = NULL,
                          isOnline = 1, lastSeenAt = excluded.lastSeenAt
            """, arguments: [UUID().uuidString, photoId, sourceId, relativePath, FolderSourceIndexer.pathKey(relativePath),
                             upload.byteCount, now])
    }

    /// Server sources that keep every one of `assetIds` in ShotDex after
    /// they leave Photos — the names Free Up Space's confirmation gives.
    /// Empty when even one would leave the library with them.
    static func keepingSources(_ db: Database, assetIds: [String]) throws -> [String] {
        var names: Set<String>?
        for assetId in assetIds {
            let photoId = try PhotoAliasResolver.photoId(db, for: assetId)
            let found = Set(try String.fetchAll(db, sql: """
                SELECT DISTINCT s.name FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.kind = 'server' AND c.missingSince IS NULL AND c.isHidden = 0
                """, arguments: [photoId]))
            if found.isEmpty { return [] }
            names = (names ?? []).union(found)
        }
        return (names ?? []).sorted()
    }
}
