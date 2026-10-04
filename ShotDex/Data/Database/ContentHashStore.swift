import Foundation
import GRDB

/// Content hashes per copy (FS-19.05 §3) — a scan result, expensive to redo.
struct ContentHashStore: Sendable {
    let database: AppDatabase

    func save(_ hash: ContentHash, copyId: String, at now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO content_hashes (copyId, algorithm, algorithmVersion, fastHash, fullHash, hashedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(copyId) DO UPDATE SET algorithm = excluded.algorithm,
                    algorithmVersion = excluded.algorithmVersion, fastHash = excluded.fastHash,
                    fullHash = excluded.fullHash, hashedAt = excluded.hashedAt
                """, arguments: [copyId, hash.algorithm, hash.version, hash.fast, hash.full, Int(now.timeIntervalSince1970)])
        }
    }

    func hash(copyId: String) throws -> ContentHash? {
        try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM content_hashes WHERE copyId = ?", arguments: [copyId]).map {
                ContentHash(algorithm: $0["algorithm"], version: $0["algorithmVersion"], fast: $0["fastHash"], full: $0["fullHash"])
            }
        }
    }

    /// Photos copies with no full hash of the current algorithm yet.
    func photosCopiesNeedingHash(limit: Int) throws -> [(copyId: String, assetId: String)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoKitId FROM photo_copies c
                LEFT JOIN content_hashes h ON h.copyId = c.id
                WHERE c.kind = 'photos' AND c.photoKitId IS NOT NULL
                  AND (h.copyId IS NULL OR h.fullHash IS NULL OR h.algorithm != ? OR h.algorithmVersion != ?)
                ORDER BY c.id LIMIT ?
                """, arguments: [ContentHash.algorithm, ContentHash.version, limit]).map { ($0["id"], $0["photoKitId"]) }
        }
    }
}
