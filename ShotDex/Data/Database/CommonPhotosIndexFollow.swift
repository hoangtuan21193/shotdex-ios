import Foundation
import GRDB

/// After a Find Common Photos run (FS-19.08 §6): the index of the
/// connection's server sources follows what the run did, from the run's own
/// rows — no rescan of the share (user 2026-11-08: "why rescan WIN?"; a
/// whole-share rescan took minutes to hours after every run).
///
/// - A **moved** photo: the copy at the path it was moved from now sits at
///   its destination (same row, photo, hashes); copies at the other paths the
///   run removed are marked missing.
/// - A **copied** photo: a new copy of the same photo at the destination,
///   with the SHA-256 the run checked.
/// - A path the index did not hold (a folder outside every source) is left;
///   the next periodic read finds what changed outside ShotDex.
enum CommonPhotosIndexFollow {
    struct Summary: Equatable, Sendable {
        var moved = 0
        var copied = 0
        var missing = 0
    }

    /// `folder` is the connection's Folder: the run's paths are from the
    /// share's root, a server source's from that folder.
    static func apply(_ db: Database, items: [CommonPhotosItem], connectionId: String, folder: String,
                      at stamp: Int) throws -> Summary {
        var summary = Summary()
        let sourceIds = try String.fetchAll(db, sql: "SELECT id FROM sources WHERE kind = 'server' AND connectionId = ?",
                                            arguments: [connectionId])
        guard !sourceIds.isEmpty else { return summary }
        for item in items {
            guard let destination = item.destinationPath, let destinationRel = relative(destination, to: folder),
                  item.status == .moved || item.status == .copied else { continue }
            let destinationKey = FolderSourceIndexer.pathKey(destinationRel)
            let modified = try Int.fetchOne(db, sql: """
                SELECT modifiedAt FROM common_photo_scan_records WHERE connectionId = ? AND path = ?
                """, arguments: [connectionId, destination])
            for sourceId in sourceIds {
                // Already indexed there (a read that ran meanwhile): nothing to follow.
                if try copyId(db, sourceId: sourceId, key: destinationKey) != nil { continue }
                let sourceKeys = item.sources.compactMap { relative($0.path, to: folder) }.map(FolderSourceIndexer.pathKey)
                if item.status == .moved {
                    let fromKey = item.movedFrom.flatMap { relative($0, to: folder) }.map(FolderSourceIndexer.pathKey)
                    guard let fromKey, let moving = try copy(db, sourceId: sourceId, key: fromKey), moving.pairedPath == nil else { continue }
                    try db.execute(sql: """
                        UPDATE photo_copies SET relativePath = ?, relativePathKey = ?, size = ?, modifiedAt = COALESCE(?, modifiedAt),
                            lastSeenAt = ?, isOnline = 1, missingSince = NULL
                        WHERE id = ?
                        """, arguments: [destinationRel, destinationKey, item.size, modified, stamp, moving.id])
                    try db.execute(sql: """
                        UPDATE copy_files SET size = ?, modifiedAt = COALESCE(?, modifiedAt), sha256 = ?, origin = 'hashed',
                            hashedAt = COALESCE(hashedAt, ?)
                        WHERE copyId = ? AND fileKey = 'primary'
                        """, arguments: [item.size, modified, item.sha256, stamp, moving.id])
                    summary.moved += 1
                    // The run's other copies of the photo, removed from the server.
                    let removed = item.sources.filter(\.isRemoved).compactMap { relative($0.path, to: folder) }
                        .map(FolderSourceIndexer.pathKey).filter { $0 != fromKey }
                    for key in removed {
                        guard let gone = try copy(db, sourceId: sourceId, key: key) else { continue }
                        try FileCopyWriter.markMissing(db, [gone.id], at: stamp)
                        summary.missing += 1
                    }
                } else {
                    // A copy of the same bytes as a copy the index holds: the same photo.
                    var original: (id: String, photoId: String, pairedPath: String?)?
                    for key in sourceKeys {
                        if let found = try copy(db, sourceId: sourceId, key: key) { original = found; break }
                    }
                    guard let original else { continue }
                    let id = UUID().uuidString
                    try db.execute(sql: """
                        INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, modifiedAt,
                                                  isOnline, lastSeenAt)
                        VALUES (?, ?, ?, 'server', ?, ?, ?, ?, 1, ?)
                        """, arguments: [id, original.photoId, sourceId, destinationRel, destinationKey, item.size, modified, stamp])
                    try db.execute(sql: """
                        INSERT INTO copy_files (copyId, fileKey, role, size, modifiedAt, sha256, origin, hashedAt)
                        VALUES (?, 'primary', ?, ?, ?, ?, 'hashed', ?)
                        """, arguments: [id, CopyFile.Role(fileName: (destinationRel as NSString).lastPathComponent).rawValue,
                                         item.size, modified, item.sha256, stamp])
                    summary.copied += 1
                }
            }
        }
        return summary
    }

    /// `Share/IMG_1.HEIC` for `photos/Share/IMG_1.HEIC` under Folder `photos`;
    /// nil for a path outside it.
    static func relative(_ path: String, to folder: String) -> String? {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !trimmed.isEmpty else { return clean }
        guard clean.hasPrefix(trimmed + "/") else { return nil }
        return String(clean.dropFirst(trimmed.count + 1))
    }

    private static func copyId(_ db: Database, sourceId: String, key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT id FROM photo_copies WHERE sourceId = ? AND relativePathKey = ?", arguments: [sourceId, key])
    }

    private static func copy(_ db: Database, sourceId: String, key: String) throws -> (id: String, photoId: String, pairedPath: String?)? {
        try Row.fetchOne(db, sql: """
            SELECT id, photoId, pairedPath FROM photo_copies WHERE sourceId = ? AND relativePathKey = ? AND missingSince IS NULL
            """, arguments: [sourceId, key]).map { ($0["id"], $0["photoId"], $0["pairedPath"]) }
    }
}
