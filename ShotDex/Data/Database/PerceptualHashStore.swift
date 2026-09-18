import Foundation
import GRDB

/// One row of `perceptual_hash`: the dHash of a photo, stamped with the
/// `modificationDate` the photo had when it was hashed so an edit re-queues it.
/// `hash` is `nil` when the thumbnail could not be read (typically an
/// iCloud-only asset with network disallowed) — kept so the scan can skip it
/// until network is allowed again instead of re-asking PhotoKit every run.
struct PerceptualHashRecord: Codable, Equatable, Sendable {
    var assetId: String
    /// `PerceptualHash.bits` as a signed bit pattern (SQLite has no UInt64).
    var hash: Int64?
    var modificationDate: Int?
    var computedAt: Int

    init(assetId: String, hash: PerceptualHash?, modificationDate: Int?, computedAt: Int) {
        self.assetId = assetId
        self.hash = hash.map { Int64(bitPattern: $0.bits) }
        self.modificationDate = modificationDate
        self.computedAt = computedAt
    }

    var perceptualHash: PerceptualHash? {
        hash.map { PerceptualHash(bits: UInt64(bitPattern: $0)) }
    }
}

extension PerceptualHashRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "perceptual_hash"
}

/// Progress of the hash side of the library: how many photos have a hash
/// against how many photos are indexed at all.
struct PerceptualHashCoverage: Equatable, Sendable {
    var hashedPhotos: Int
    var indexedPhotos: Int
}

/// When a strictness level was last grouped and how many groups it produced.
struct DuplicateScanState: Equatable, Sendable {
    var strictness: DuplicateStrictness
    var scannedAt: Date
    var groupCount: Int
}

/// Reads and writes the perceptual hashes the duplicate finder works from.
///
/// Separate table rather than a `photo_metadata` column for the same reason
/// as `PlaceStore`: the indexer upserts whole `PhotoMetadata` records and a
/// column it does not know about would be blanked on every re-index.
struct PerceptualHashStore: Sendable {
    let database: AppDatabase

    // MARK: Work list

    /// Indexed photos (not videos) that still need hashing, newest first: no
    /// hash row yet, or a row from before the photo was last modified. Rows
    /// whose last read failed (`hash IS NULL`) are included only when
    /// `retryingFailed` — i.e. when the network is allowed this run.
    func pendingAssetIds(retryingFailed: Bool) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT p.assetId
                    FROM photo_metadata p
                    LEFT JOIN perceptual_hash h ON h.assetId = p.assetId
                    WHERE p.mediaType = ?
                      AND (h.assetId IS NULL
                           OR h.modificationDate IS NOT p.modificationDate
                           OR (h.hash IS NULL AND ?))
                    ORDER BY p.creationDate DESC
                    """,
                arguments: [MediaKind.photo.storedValue, retryingFailed]
            )
        }
    }

    /// Rows for assets that left the library (their `photo_metadata` row is
    /// gone). Returns how many were removed.
    func pruneOrphans() throws -> Int {
        try database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM perceptual_hash WHERE assetId NOT IN (SELECT assetId FROM photo_metadata)"
            )
            return db.changesCount
        }
    }

    // MARK: Writes

    func upsert(_ records: [PerceptualHashRecord]) throws {
        guard !records.isEmpty else { return }
        try database.writer.write { db in
            for record in records {
                try record.upsert(db)
            }
        }
    }

    func delete(assetIds: [String]) throws {
        guard !assetIds.isEmpty else { return }
        _ = try database.writer.write { db in
            try PerceptualHashRecord.deleteAll(db, keys: assetIds)
        }
    }

    // MARK: Reads

    /// Every hashed photo with the facts the grouper orders on. Videos never
    /// have a hash row, and failed reads (`hash IS NULL`) are left out.
    func hashedPhotos() throws -> [HashedPhoto] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT p.assetId, h.hash, p.width, p.height, p.fileSize, p.creationDate, p.isFavorite
                    FROM perceptual_hash h
                    JOIN photo_metadata p ON p.assetId = h.assetId
                    WHERE h.hash IS NOT NULL AND p.mediaType = ?
                    """,
                arguments: [MediaKind.photo.storedValue]
            ).map { row in
                let stored: Int64 = row["hash"]
                return HashedPhoto(
                    assetId: row["assetId"],
                    hash: PerceptualHash(bits: UInt64(bitPattern: stored)),
                    width: row["width"],
                    height: row["height"],
                    fileSize: row["fileSize"],
                    creationDate: row["creationDate"],
                    isFavorite: row["isFavorite"] ?? false
                )
            }
        }
    }

    /// How many indexed photos the next scan would hash.
    func pendingCount(retryingFailed: Bool) throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM photo_metadata p
                    LEFT JOIN perceptual_hash h ON h.assetId = p.assetId
                    WHERE p.mediaType = ?
                      AND (h.assetId IS NULL
                           OR h.modificationDate IS NOT p.modificationDate
                           OR (h.hash IS NULL AND ?))
                    """,
                arguments: [MediaKind.photo.storedValue, retryingFailed]
            ) ?? 0
        }
    }

    // MARK: Group cache

    /// Replaces the cached groups of `strictness` with `groups` and stamps the
    /// scan state. One transaction, so a reader never sees a half-written cache.
    func replaceGroups(_ groups: [DuplicateGroup], strictness: DuplicateStrictness, scannedAt: Date) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM duplicate_groups WHERE strictness = ?", arguments: [strictness.rawValue])
            for group in groups {
                for member in group.members {
                    try db.execute(
                        sql: "INSERT INTO duplicate_groups (strictness, groupId, assetId) VALUES (?, ?, ?)",
                        arguments: [strictness.rawValue, group.id, member.assetId]
                    )
                }
            }
            try db.execute(
                sql: """
                    INSERT INTO duplicate_scan_state (strictness, scannedAt, groupCount) VALUES (?, ?, ?)
                    ON CONFLICT(strictness) DO UPDATE SET scannedAt = excluded.scannedAt, groupCount = excluded.groupCount
                    """,
                arguments: [strictness.rawValue, Int(scannedAt.timeIntervalSince1970), groups.count]
            )
        }
    }

    func scanState(strictness: DuplicateStrictness) throws -> DuplicateScanState? {
        try database.reader.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT scannedAt, groupCount FROM duplicate_scan_state WHERE strictness = ?",
                arguments: [strictness.rawValue]
            ).map { row in
                let scannedAt: Int = row["scannedAt"]
                return DuplicateScanState(
                    strictness: strictness,
                    scannedAt: Date(timeIntervalSince1970: TimeInterval(scannedAt)),
                    groupCount: row["groupCount"]
                )
            }
        }
    }

    /// The cached groups of `strictness`, rebuilt with current facts from
    /// `photo_metadata`. Members whose photo or hash row is gone drop out, and a
    /// group left with one member is not returned. `nil` when this strictness
    /// has never been grouped.
    func cachedGroups(strictness: DuplicateStrictness) throws -> [DuplicateGroup]? {
        try database.reader.read { db in
            let hasState = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM duplicate_scan_state WHERE strictness = ?)",
                arguments: [strictness.rawValue]
            ) ?? false
            guard hasState else { return nil }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT g.groupId, p.assetId, h.hash, p.width, p.height, p.fileSize, p.creationDate, p.isFavorite
                    FROM duplicate_groups g
                    JOIN photo_metadata p ON p.assetId = g.assetId
                    JOIN perceptual_hash h ON h.assetId = g.assetId
                    WHERE g.strictness = ? AND h.hash IS NOT NULL
                    """,
                arguments: [strictness.rawValue]
            )
            var membersByGroup: [String: [HashedPhoto]] = [:]
            for row in rows {
                let stored: Int64 = row["hash"]
                let photo = HashedPhoto(
                    assetId: row["assetId"],
                    hash: PerceptualHash(bits: UInt64(bitPattern: stored)),
                    width: row["width"],
                    height: row["height"],
                    fileSize: row["fileSize"],
                    creationDate: row["creationDate"],
                    isFavorite: row["isFavorite"] ?? false
                )
                membersByGroup[row["groupId"], default: []].append(photo)
            }
            return DuplicateGrouper.assemble(membersByGroup.values.map(Array.init))
        }
    }

    /// Drops deleted photos out of every cached group.
    func removeFromGroups(assetIds: [String]) throws {
        guard !assetIds.isEmpty else { return }
        try database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM duplicate_groups WHERE assetId IN (\(databaseQuestionMarks(count: assetIds.count)))",
                arguments: StatementArguments(assetIds)
            )
        }
    }

    func coverage() throws -> PerceptualHashCoverage {
        try database.reader.read { db in
            let hashed = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM perceptual_hash h
                    JOIN photo_metadata p ON p.assetId = h.assetId
                    WHERE h.hash IS NOT NULL AND p.mediaType = ?
                    """,
                arguments: [MediaKind.photo.storedValue]
            ) ?? 0
            let indexed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM photo_metadata WHERE mediaType = ?",
                arguments: [MediaKind.photo.storedValue]
            ) ?? 0
            return PerceptualHashCoverage(hashedPhotos: hashed, indexedPhotos: indexed)
        }
    }
}
