import Foundation
import GRDB

/// What a folder read and a server read both do with one file (FS-19.05):
/// match it to the copy it was, record photo, copy, fast hash and metadata
/// in one transaction, and mark what a complete read did not find.
enum FileCopyWriter {
    /// A copy this source knew that is not at its path any more.
    struct Vanished: Sendable {
        let copyId: String
        let photoId: String
        let size: Int64?
        let fast: String?
    }

    /// Copies of `sourceId` whose path is not in `listed`: a renamed or moved
    /// file is matched back to one of these by its fast hash and size
    /// (FS-19.02 §2); what is left over went missing.
    static func vanished(_ db: Database, sourceId: String, kind: String, listed: Set<String>) throws -> [Vanished] {
        try Row.fetchAll(db, sql: """
            SELECT c.id, c.photoId, c.relativePathKey, c.size, h.fastHash FROM photo_copies c
            LEFT JOIN content_hashes h ON h.copyId = c.id
            WHERE c.sourceId = ? AND c.kind = ?
            """, arguments: [sourceId, kind])
            .filter { !listed.contains($0["relativePathKey"] as String) }
            .map { Vanished(copyId: $0["id"], photoId: $0["photoId"], size: $0["size"], fast: $0["fastHash"]) }
    }

    /// The copy already recorded at a path.
    struct Existing: Sendable {
        let id: String
        let photoId: String
        let size: Int64?
        let modifiedAt: Int?
        /// False when Clear Local Metadata Index took the row away — then a
        /// file the same as before is still read again (FS-19.05 §7).
        let hasMetadata: Bool
    }

    static func existing(_ db: Database, sourceId: String, key: String) throws -> Existing? {
        try Row.fetchOne(db, sql: """
            SELECT c.id, c.photoId, c.size, c.modifiedAt,
                   EXISTS(SELECT 1 FROM photo_metadata m WHERE m.assetId = c.photoId) AS hasMetadata
            FROM photo_copies c WHERE c.sourceId = ? AND c.relativePathKey = ?
            """, arguments: [sourceId, key]).map {
            Existing(id: $0["id"], photoId: $0["photoId"], size: $0["size"], modifiedAt: $0["modifiedAt"], hasMetadata: $0["hasMetadata"])
        }
    }

    /// True when `existing` is the file as last read: same size, same date,
    /// metadata row still there.
    static func isUnchanged(_ existing: Existing?, size: Int64, modified: Int?) -> Bool {
        guard let existing else { return false }
        return existing.size == size && existing.modifiedAt == modified && existing.hasMetadata
    }

    /// Seen again, unchanged: online, present, and — Put Back — no orphan.
    static func touch(_ db: Database, existing: Existing, at stamp: Int) throws {
        try db.execute(sql: "UPDATE photo_copies SET lastSeenAt = ?, isOnline = 1, missingSince = NULL WHERE id = ?",
                       arguments: [stamp, existing.id])
        try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ? AND orphanedAt IS NOT NULL",
                       arguments: [existing.photoId])
    }

    /// True when this copy's new fast hash differs from its old one and
    /// another present copy of the same photo still carries the old one
    /// (FS-19.02 §2). A photo with only this copy keeps its id: same source,
    /// same path, new bytes is the same photo edited elsewhere.
    static func changedPictureWhileOthersKeepOld(_ db: Database, copyId: String, photoId: String, newFast: String) throws -> Bool {
        guard let old = try String.fetchOne(db, sql: "SELECT fastHash FROM content_hashes WHERE copyId = ?", arguments: [copyId]),
              old != newFast else { return false }
        return try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM photo_copies c JOIN content_hashes h ON h.copyId = c.id
                          WHERE c.photoId = ? AND c.id != ? AND c.missingSince IS NULL AND h.fastHash = ?)
            """, arguments: [photoId, copyId, old]) == true
    }

    struct Copy: Sendable {
        var photoId: String
        var copyId: String
        let sourceId: String
        /// `file` · `server`
        let kind: String
        let relativePath: String
        let key: String
        let size: Int64
        let modified: Int?
        let pairedPath: String?
        let sidecarStamp: String?
    }

    /// One file read: its photo, its copy, its fast hash, its metadata row
    /// and what its sidecar or own XMP says. `splitFrom` set: the copy now
    /// holds another picture and leaves its old photo first.
    static func record(_ db: Database, _ copy: Copy, hash: ContentHash, metadata: PhotoMetadata,
                       marks: SidecarValues?, marksAt: Int, splitFrom: String?, at stamp: Int) throws {
        if splitFrom != nil {
            try PhotoIdentityStore.split(db, copyId: copy.copyId, into: copy.photoId, now: stamp)
        }
        try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, ?)", arguments: [copy.photoId, stamp])
        try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ?", arguments: [copy.photoId])
        try db.execute(sql: """
            INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, modifiedAt, pairedPath,
                                      sidecarStamp, isOnline, lastSeenAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(id) DO UPDATE SET relativePath = excluded.relativePath, relativePathKey = excluded.relativePathKey,
                size = excluded.size, modifiedAt = excluded.modifiedAt, pairedPath = excluded.pairedPath,
                sidecarStamp = excluded.sidecarStamp,
                isOnline = 1, missingSince = NULL, isCloudPlaceholder = 0, lastSeenAt = excluded.lastSeenAt
            """, arguments: [copy.copyId, copy.photoId, copy.sourceId, copy.kind, copy.relativePath, copy.key, copy.size,
                             copy.modified, copy.pairedPath, copy.sidecarStamp, stamp])
        try db.execute(sql: """
            INSERT INTO content_hashes (copyId, algorithm, algorithmVersion, fastHash, fullHash, hashedAt)
            VALUES (?, ?, ?, ?, NULL, ?)
            ON CONFLICT(copyId) DO UPDATE SET algorithm = excluded.algorithm, algorithmVersion = excluded.algorithmVersion,
                fastHash = excluded.fastHash, fullHash = NULL, hashedAt = excluded.hashedAt
            """, arguments: [copy.copyId, hash.algorithm, hash.version, hash.fast, stamp])
        try metadata.upsert(db)
        if let marks {
            try PhotoUserMarksStore.applySidecar(db, values: marks, photoId: copy.photoId, at: marksAt)
        }
    }

    /// Files a complete read no longer finds: the copy stays (its hash is
    /// what joins the file back when it returns) and is marked missing; a
    /// photo left with no present copy becomes an orphan (FS-19.05 §5).
    static func markMissing(_ db: Database, _ copyIds: [String], at stamp: Int) throws {
        guard !copyIds.isEmpty else { return }
        let marks = databaseQuestionMarks(count: copyIds.count)
        try db.execute(sql: "UPDATE photo_copies SET missingSince = ? WHERE id IN (\(marks)) AND missingSince IS NULL",
                       arguments: StatementArguments([stamp] + copyIds))
        try db.execute(sql: """
            UPDATE photos SET orphanedAt = ?
            WHERE orphanedAt IS NULL AND id IN (SELECT photoId FROM photo_copies WHERE id IN (\(marks)))
              AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = photos.id AND c.missingSince IS NULL)
            """, arguments: StatementArguments([stamp] + copyIds))
    }
}
