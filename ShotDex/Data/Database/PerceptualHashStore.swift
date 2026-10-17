import Foundation
import GRDB
import Photos

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

/// When the library was last grouped and how many groups it produced.
struct DuplicateScanState: Equatable, Sendable {
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
                    SELECT p.assetId, h.hash, p.width, p.height, p.fileSize, p.creationDate, p.isFavorite, p.modificationDate, p.focalLength, p.mediaSubtypes, p.cameraModel
                    FROM perceptual_hash h
                    JOIN photo_metadata p ON p.assetId = h.assetId
                    WHERE h.hash IS NOT NULL AND p.mediaType = ?
                    """,
                arguments: [MediaKind.photo.storedValue]
            ).map(Self.hashedPhoto)
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

    /// Replaces the cached groups with `groups` and stamps the scan state.
    /// One transaction, so a reader never sees a half-written cache. Groups
    /// are per source (FS-19.04 §4); the Photos library is the only source
    /// that scans today.
    func replaceGroups(_ groups: [DuplicateGroup], scannedAt: Date, sourceId: String = PhotoLibrarySource.id) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM duplicate_groups WHERE sourceId = ?", arguments: [sourceId])
            for group in groups {
                for member in group.members {
                    try db.execute(
                        sql: "INSERT INTO duplicate_groups (sourceId, groupId, assetId, kind) VALUES (?, ?, ?, ?)",
                        arguments: [sourceId, group.id, member.assetId, group.kind.rawValue]
                    )
                }
            }
            try db.execute(
                sql: """
                    INSERT INTO duplicate_scan_state (sourceId, scannedAt, groupCount) VALUES (?, ?, ?)
                    ON CONFLICT(sourceId) DO UPDATE SET scannedAt = excluded.scannedAt, groupCount = excluded.groupCount
                    """,
                arguments: [sourceId, Int(scannedAt.timeIntervalSince1970), groups.count]
            )
        }
    }

    func scanState(sourceId: String = PhotoLibrarySource.id) throws -> DuplicateScanState? {
        try database.reader.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT scannedAt, groupCount FROM duplicate_scan_state WHERE sourceId = ?",
                arguments: [sourceId]
            ).map { row in
                let scannedAt: Int = row["scannedAt"]
                return DuplicateScanState(
                    scannedAt: Date(timeIntervalSince1970: TimeInterval(scannedAt)),
                    groupCount: row["groupCount"]
                )
            }
        }
    }

    /// The cached groups, rebuilt with current facts from `photo_metadata`.
    /// Members whose photo or hash row is gone drop out, and a group left
    /// with one member is not returned. `nil` when never grouped.
    func cachedGroups(sourceId: String = PhotoLibrarySource.id) throws -> [DuplicateGroup]? {
        try database.reader.read { db in
            let hasState = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM duplicate_scan_state WHERE sourceId = ?)",
                arguments: [sourceId]
            ) ?? false
            guard hasState else { return nil }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT g.groupId, g.kind, p.assetId, h.hash, p.width, p.height, p.fileSize, p.creationDate, p.isFavorite,
                           p.modificationDate, p.focalLength, p.mediaSubtypes, p.cameraModel
                    FROM duplicate_groups g
                    JOIN photo_metadata p ON p.assetId = g.assetId
                    JOIN perceptual_hash h ON h.assetId = g.assetId
                    WHERE g.sourceId = ? AND h.hash IS NOT NULL
                    """,
                arguments: [sourceId]
            )

            var membersByGroup: [String: (kind: DuplicateKind, members: [HashedPhoto])] = [:]
            for row in rows {
                // A kind this build does not know regroups as a look-alike
                // rather than dropping the group.
                let kind = DuplicateKind(rawValue: row["kind"]) ?? .lookAlikes
                membersByGroup[row["groupId"], default: (kind, [])].members.append(Self.hashedPhoto(row))
            }
            return DuplicateGrouper.assemble(membersByGroup.values.map { ($0.kind, $0.members) })
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

    /// One hash row joined to its `photo_metadata` facts.
    private static func hashedPhoto(_ row: Row) -> HashedPhoto {
        let stored: Int64 = row["hash"]
        let subtypes: Int? = row["mediaSubtypes"]
        let cameraModel: String? = row["cameraModel"]
        return HashedPhoto(
            assetId: row["assetId"],
            hash: PerceptualHash(bits: UInt64(bitPattern: stored)),
            width: row["width"],
            height: row["height"],
            fileSize: row["fileSize"],
            creationDate: row["creationDate"],
            isFavorite: row["isFavorite"] ?? false,
            modificationDate: row["modificationDate"],
            focalLength: row["focalLength"],
            isScreenshot: subtypes.map { $0 & Int(PHAssetMediaSubtype.photoScreenshot.rawValue) != 0 } ?? false,
            hasCameraEXIF: !(cameraModel ?? "").isEmpty
        )
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
