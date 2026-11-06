import Foundation
import GRDB

/// One original file of a copy (FS-19.07 §3) and what is known of its bytes.
struct CopyFile: Hashable, Sendable {
    /// What the file is to its photo — which files must all be on a server
    /// for the photo to count as there.
    enum Role: String, Sendable {
        case photo, raw, video, pairedVideo, audio
        /// The render of an edit made in Photos.
        case editedPhoto, editedVideo, editedPairedVideo

        /// A Photos resource, by `PHAssetResourceType` raw value — the
        /// prefix of the resource key. Nil for what is not a file of the
        /// photo (adjustment data, proxies).
        init?(resourceType: Int, isRAW: Bool) {
            switch resourceType {
            case 1, 4: self = isRAW ? .raw : .photo
            case 2: self = .video
            case 3: self = .audio
            case 5: self = .editedPhoto
            case 6: self = .editedVideo
            case 9: self = .pairedVideo
            case 10: self = .editedPairedVideo
            default: return nil
            }
        }

        /// A file on a server or in a folder, by its name.
        init(fileName: String) {
            if FolderEnumeration.isMovie(URL(fileURLWithPath: fileName)) {
                self = .video
            } else if FileTypeBadge.isRAW(filename: fileName) {
                self = .raw
            } else {
                self = .photo
            }
        }
    }

    enum Origin: String, Sendable {
        /// Taken from Backup's records — the ledger, or the destination index.
        case backup
        /// Read whole and hashed here.
        case hashed
        /// Hashed by another device, over iCloud (FS-19.07 §12.3).
        case shared
        /// Hashed by another device, read from the ledger on the NAS
        /// (§12.2).
        case ledger

        /// Worked out elsewhere: `CopyFile.sharedFrom` says by whom, and a
        /// random check may drop it (§12.4).
        var isFromAnotherDevice: Bool { self == .shared || self == .ledger }
    }

    var copyId: String
    var fileKey: String
    var role: Role
    var size: Int64?
    var modifiedAt: Int?
    var stamp: String?
    var sha256: String?
    var origin: Origin?
    /// The device that hashed it, for `shared` and `ledger`.
    var sharedFrom: String?
    var attempts = 0
    var lastError: String?
    var triedAt: Int?
}

/// A Photos asset's file as PhotoKit lists it, before anything is read.
struct PhotosFile: Hashable, Sendable {
    var fileKey: String
    var role: CopyFile.Role
    var size: Int64?
    /// Backup's source stamp for the same file (`PhotoKitBackupSource`).
    var stamp: String
}

/// The per-file hashes behind "is it on the server" (FS-19.07 §4, §5).
struct CopyFileStore: Sendable {
    /// Before the Photos copies of `assetIds` are deleted: their listed
    /// files and hashes go too. No foreign key does it, and the rows were
    /// left behind for every photo deleted from Photos (2026-11-02).
    static func deletePhotosFiles(_ db: Database, assetIds: [String]) throws {
        guard !assetIds.isEmpty else { return }
        let copies = "SELECT id FROM photo_copies WHERE kind = 'photos' AND photoKitId IN (\(databaseQuestionMarks(count: assetIds.count)))"
        try db.execute(sql: "DELETE FROM copy_files WHERE copyId IN (\(copies))", arguments: StatementArguments(assetIds))
        try db.execute(sql: "DELETE FROM copy_file_listings WHERE copyId IN (\(copies))", arguments: StatementArguments(assetIds))
    }

    let database: AppDatabase

    // MARK: - Photos

    /// Assets whose files PhotoKit has not listed, or listed before their
    /// last edit — what joined the library last first (`indexedAt`), then
    /// newest capture (FS-19.07 §4, AC-114).
    func photosCopiesNeedingListing(limit: Int) throws -> [(copyId: String, assetId: String, stamp: Int?)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoKitId, m.modificationDate FROM photo_copies c
                JOIN photo_metadata m ON m.assetId = c.photoKitId
                LEFT JOIN copy_file_listings l ON l.copyId = c.id
                WHERE c.kind = 'photos' AND c.photoKitId IS NOT NULL
                  AND (l.copyId IS NULL OR l.stamp IS NOT m.modificationDate)
                ORDER BY m.indexedAt DESC, m.creationDate DESC, c.id LIMIT ?
                """, arguments: [limit]).map { ($0[0], $0[1], $0[2]) }
        }
    }

    /// Writes what PhotoKit listed for one asset. A file whose stamp did not
    /// change keeps its hash; a file the asset no longer has goes.
    func saveListing(copyId: String, stamp: Int?, files: [PhotosFile], at now: Date = Date()) throws {
        let time = Int(now.timeIntervalSince1970)
        try database.writer.write { db in
            for file in files {
                try db.execute(sql: """
                    INSERT INTO copy_files (copyId, fileKey, role, size, stamp) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(copyId, fileKey) DO UPDATE SET role = excluded.role, size = excluded.size,
                        stamp = excluded.stamp,
                        sha256 = CASE WHEN stamp IS excluded.stamp THEN sha256 END,
                        origin = CASE WHEN stamp IS excluded.stamp THEN origin END,
                        sharedFrom = CASE WHEN stamp IS excluded.stamp THEN sharedFrom END,
                        hashedAt = CASE WHEN stamp IS excluded.stamp THEN hashedAt END,
                        attempts = CASE WHEN stamp IS excluded.stamp THEN attempts ELSE 0 END,
                        lastError = CASE WHEN stamp IS excluded.stamp THEN lastError END,
                        triedAt = CASE WHEN stamp IS excluded.stamp THEN triedAt END
                    """, arguments: [copyId, file.fileKey, file.role.rawValue, file.size, file.stamp])
            }
            let keys = files.map(\.fileKey)
            try db.execute(sql: """
                DELETE FROM copy_files WHERE copyId = ? AND fileKey NOT IN (SELECT value FROM json_each(?))
                """, arguments: [copyId, String(data: try JSONEncoder().encode(keys), encoding: .utf8)])
            try db.execute(sql: """
                INSERT INTO copy_file_listings (copyId, stamp, listedAt) VALUES (?, ?, ?)
                ON CONFLICT(copyId) DO UPDATE SET stamp = excluded.stamp, listedAt = excluded.listedAt
                """, arguments: [copyId, stamp, time])
        }
    }

    /// Fills a Photos file's hash from Backup's ledger when the ledger holds
    /// the same file with the same stamp (FS-19.07 §4) — nothing is
    /// downloaded for what Backup already copied. Returns how many it filled.
    @discardableResult
    func seedFromBackupLedger(at now: Date = Date()) throws -> Int {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE copy_files SET sha256 = m.sha256, origin = 'backup', sharedFrom = NULL, hashedAt = ?, lastError = NULL
                FROM (
                    SELECT f.copyId, f.fileKey, MIN(l.sha256) AS sha256 FROM copy_files f
                    JOIN photo_copies c ON c.id = f.copyId AND c.kind = 'photos'
                    JOIN backup_jobs j ON j.sourceId = ?
                    JOIN backup_ledger l ON l.jobId = j.id AND l.itemKey = c.photoKitId
                        AND l.resourceKey = f.fileKey AND l.sourceStamp = f.stamp AND l.sha256 IS NOT NULL
                    WHERE f.sha256 IS NULL
                    GROUP BY f.copyId, f.fileKey
                ) AS m
                WHERE copy_files.copyId = m.copyId AND copy_files.fileKey = m.fileKey
                """, arguments: [Int(now.timeIntervalSince1970), PhotoLibrarySource.id])
            return db.changesCount
        }
    }

    /// A Photos file worth downloading to hash (FS-19.07 §4): no hash yet,
    /// and a file of the same size on some server copy — without one, the
    /// photo is already known not to be there. Photos does not always report
    /// a size; such a file is a candidate while any server file is known.
    /// Newest photo first; a file tried since `triedBefore` waits for the
    /// next pass. `everything` (the Mac hashing for every device, §12.1)
    /// drops the size test: every file is a candidate, and what was indexed
    /// last goes first (`indexedAt`, rewritten on a re-index — the same
    /// order as the listing queue); a photo with no metadata row goes last.
    func photosCandidates(triedBefore: Date, limit: Int, everything: Bool = false)
        throws -> [(copyId: String, assetId: String, fileKey: String, size: Int64?)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.copyId, c.photoKitId, f.fileKey, f.size FROM copy_files f
                JOIN photo_copies c ON c.id = f.copyId AND c.kind = 'photos' AND c.photoKitId IS NOT NULL
                LEFT JOIN photo_metadata m ON m.assetId = c.photoKitId
                WHERE f.sha256 IS NULL AND (f.triedAt IS NULL OR f.triedAt < ?)
                  AND (\(everything ? "f.attempts < \(Self.everythingAttempts)" : "0") OR EXISTS (
                    SELECT 1 FROM copy_files s JOIN photo_copies sc ON sc.id = s.copyId
                    WHERE sc.kind = 'server' AND sc.missingSince IS NULL AND (f.size IS NULL OR s.size = f.size)))
                ORDER BY \(everything ? "COALESCE(m.indexedAt, 0) DESC, " : "")m.creationDate DESC, f.copyId, f.fileKey LIMIT ?
                """, arguments: [Int(triedBefore.timeIntervalSince1970), limit]).map { ($0[0], $0[1], $0[2], $0[3]) }
        }
    }

    // MARK: - Server

    /// A server file as the listing gave it.
    struct ListedFile: Sendable {
        var fileKey: String
        var relativePath: String
        var size: Int64
        var modifiedAt: Int?
    }

    /// Writes a server copy's files from the listing, inside the indexer's
    /// write. A file whose size and date did not change keeps its hash —
    /// also after a move, since the copy keeps its id (FS-19.07 §5).
    static func saveServerFiles(_ db: Database, copyId: String, files: [ListedFile]) throws {
        for file in files {
            let role = CopyFile.Role(fileName: (file.relativePath as NSString).lastPathComponent)
            try db.execute(sql: """
                INSERT INTO copy_files (copyId, fileKey, role, size, modifiedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(copyId, fileKey) DO UPDATE SET role = excluded.role, size = excluded.size,
                    modifiedAt = excluded.modifiedAt,
                    sha256 = CASE WHEN \(Self.sameFile) THEN sha256 END,
                    origin = CASE WHEN \(Self.sameFile) THEN origin END,
                    sharedFrom = CASE WHEN \(Self.sameFile) THEN sharedFrom END,
                    hashedAt = CASE WHEN \(Self.sameFile) THEN hashedAt END,
                    attempts = CASE WHEN \(Self.sameFile) THEN attempts ELSE 0 END,
                    lastError = CASE WHEN \(Self.sameFile) THEN lastError END,
                    triedAt = CASE WHEN \(Self.sameFile) THEN triedAt END
                """, arguments: [copyId, file.fileKey, role.rawValue, file.size, file.modifiedAt])
        }
        let keys = String(data: try JSONEncoder().encode(files.map(\.fileKey)), encoding: .utf8)
        try db.execute(sql: "DELETE FROM copy_files WHERE copyId = ? AND fileKey NOT IN (SELECT value FROM json_each(?))",
                       arguments: [copyId, keys])
    }

    private static let sameFile = "size IS excluded.size AND modifiedAt IS excluded.modifiedAt"

    /// A server copy's file with no hash yet, and where it sits.
    struct UnhashedServerFile: Sendable {
        var copyId: String
        var fileKey: String
        var relativePath: String
        var size: Int64
        /// The listing's write time; nil when the server gave none.
        var modifiedAt: Int? = nil
    }

    /// Files of the source's server copies with no hash — the primary at the
    /// copy's path, the companion at its paired path.
    func unhashedServerFiles(sourceId: String) throws -> [UnhashedServerFile] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.copyId, f.fileKey, f.size, f.modifiedAt,
                       CASE f.fileKey WHEN 'companion' THEN c.pairedPath ELSE c.relativePath END AS path
                FROM copy_files f JOIN photo_copies c ON c.id = f.copyId
                WHERE c.sourceId = ? AND c.kind = 'server' AND c.missingSince IS NULL
                  AND f.sha256 IS NULL AND f.size IS NOT NULL
                """, arguments: [sourceId]).compactMap { row in
                guard let path: String = row["path"] else { return nil }
                return UnhashedServerFile(copyId: row["copyId"], fileKey: row["fileKey"], relativePath: path, size: row["size"],
                                          modifiedAt: row["modifiedAt"])
            }
        }
    }

    /// What Backup knows of the files it wrote on a connection — its ledger
    /// and the destination index, which holds other phones' files too — by
    /// path key from the server's root: size and SHA-256.
    func backupRecords(connectionId: String) throws -> [String: (size: Int64, sha256: String)] {
        try database.reader.read { db in
            var out: [String: (Int64, String)] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT j.folder, d.path, d.size, d.sha256 FROM backup_destination_files d
                JOIN backup_jobs j ON j.id = d.jobId
                WHERE j.connectionId = ? AND d.sha256 IS NOT NULL
                """, arguments: [connectionId]) {
                out[FolderSourceIndexer.pathKey(ServerUploadPath.join(row[0], row[1]))] = (row[2], row[3])
            }
            // The ledger's own uploads win: written and read back by this device.
            for row in try Row.fetchAll(db, sql: """
                SELECT l.remotePath, l.byteCount, l.sha256 FROM backup_ledger l
                JOIN backup_jobs j ON j.id = l.jobId
                WHERE j.connectionId = ? AND l.outcome = 'uploaded'
                  AND l.remotePath IS NOT NULL AND l.byteCount IS NOT NULL AND l.sha256 IS NOT NULL
                """, arguments: [connectionId]) {
                out[FolderSourceIndexer.pathKey(row[0])] = (row[1], row[2])
            }
            return out
        }
    }

    /// Server files worth reading whole (FS-19.07 §5): no hash yet, and the
    /// size of a Photos file that is not matched on this source — unhashed,
    /// or hashed with no server file of the same bytes here. A file tried
    /// since `triedBefore` waits for the next pass. `everything` (§12.1)
    /// drops the size test: every unhashed file of the source whose size
    /// the listing gave.
    func serverCandidates(sourceId: String, triedBefore: Date, limit: Int, everything: Bool = false) throws -> [UnhashedServerFile] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.copyId, f.fileKey, f.size,
                       CASE f.fileKey WHEN 'companion' THEN c.pairedPath ELSE c.relativePath END AS path
                FROM copy_files f JOIN photo_copies c ON c.id = f.copyId
                WHERE c.sourceId = ?1 AND c.kind = 'server' AND c.missingSince IS NULL
                  AND f.sha256 IS NULL AND f.size IS NOT NULL AND (f.triedAt IS NULL OR f.triedAt < ?2)
                  AND (\(everything ? "f.attempts < \(Self.everythingAttempts)" : "0") OR EXISTS (
                    SELECT 1 FROM copy_files p JOIN photo_copies pc ON pc.id = p.copyId AND pc.kind = 'photos'
                    WHERE p.size = f.size AND (p.sha256 IS NULL OR NOT EXISTS (
                        SELECT 1 FROM copy_files s JOIN photo_copies sc ON sc.id = s.copyId
                        WHERE s.sha256 = p.sha256 AND sc.sourceId = ?1 AND sc.kind = 'server' AND sc.missingSince IS NULL))))
                ORDER BY c.relativePathKey, f.fileKey LIMIT ?3
                """, arguments: [sourceId, Int(triedBefore.timeIntervalSince1970), limit]).compactMap { row in
                guard let path: String = row["path"] else { return nil }
                return UnhashedServerFile(copyId: row["copyId"], fileKey: row["fileKey"], relativePath: path, size: row["size"])
            }
        }
    }

    /// Hashing everything, a file that failed this many times is left —
    /// a resource iCloud will not hand over would be fetched every pass for
    /// a photo that may never be asked about. It is still hashed when a
    /// server file of its size makes it a real candidate.
    static let everythingAttempts = 5

    /// `sharedFrom` names the device for a hash from another one (§12);
    /// `hashedAt` is then when that device hashed it, so a later random
    /// check can drop what it sent before being caught wrong.
    /// A hash from another device fills only a file still unhashed — one
    /// worked out here meanwhile is kept. Returns whether the row changed.
    @discardableResult
    func saveHash(_ sha256: String, copyId: String, fileKey: String, origin: CopyFile.Origin, sharedFrom: String? = nil,
                  hashedAt: Date? = nil, at now: Date = Date()) throws -> Bool {
        let time = Int(now.timeIntervalSince1970)
        return try database.writer.write { db in
            try db.execute(sql: """
                UPDATE copy_files SET sha256 = ?, origin = ?, sharedFrom = ?, hashedAt = ?, triedAt = ?, lastError = NULL,
                    sharedAt = NULL
                WHERE copyId = ? AND fileKey = ? AND (? = 0 OR sha256 IS NULL)
                """, arguments: [sha256, origin.rawValue, origin.isFromAnotherDevice ? (sharedFrom ?? Self.unknownDevice) : nil,
                                 // Never later than now: a sender whose clock runs ahead
                                 // must not slip a hash past a distrust (§12.4).
                                 // A shared hash with no time counts as oldest: dropped by
                                 // any distrust, never let back in by one.
                                 min(Int((hashedAt ?? (origin.isFromAnotherDevice ? Date(timeIntervalSince1970: 0) : now))
                                     .timeIntervalSince1970), time), time, copyId, fileKey, origin.isFromAnotherDevice])
            return db.changesCount > 0
        }
    }

    // MARK: - The ledger on the NAS (FS-19.07 §12.2)

    /// One line of a source's ledger as kept here.
    struct LedgerLine: Equatable, Sendable {
        var pathKey: String
        var device: String
        var size: Int64
        var modifiedAt: Int?
        var sha256: String
        var recordedAt: Int
    }

    /// Segments of the source's ledger read, by name, with the size read.
    func ledgerSegments(sourceId: String) throws -> [String: Int64] {
        try database.reader.read { db in
            Dictionary(try Row.fetchAll(db, sql: "SELECT segment, size FROM hash_index_segments WHERE sourceId = ?",
                                        arguments: [sourceId]).map { ($0["segment"], $0["size"]) },
                       uniquingKeysWith: { first, _ in first })
        }
    }

    /// A segment read (or written) and its lines, in one write: a line
    /// newer than the one kept for its path and device replaces it.
    func saveLedgerLines(_ lines: [LedgerLine], sourceId: String, segment: String, size: Int64) throws {
        try database.writer.write { db in
            let insert = try db.cachedStatement(sql: """
                INSERT INTO hash_index_lines (sourceId, pathKey, device, size, modifiedAt, sha256, recordedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(sourceId, pathKey, device) DO UPDATE SET size = excluded.size,
                    modifiedAt = excluded.modifiedAt, sha256 = excluded.sha256, recordedAt = excluded.recordedAt
                WHERE excluded.recordedAt >= hash_index_lines.recordedAt
                """)
            for line in lines {
                try insert.execute(arguments: [sourceId, line.pathKey, line.device, line.size, line.modifiedAt, line.sha256, line.recordedAt])
            }
            try db.execute(sql: """
                INSERT INTO hash_index_segments (sourceId, segment, size) VALUES (?, ?, ?)
                ON CONFLICT(sourceId, segment) DO UPDATE SET size = excluded.size
                """, arguments: [sourceId, segment, size])
        }
    }

    /// The kept lines of the source for these path keys only — a source's
    /// whole ledger (200k lines) is never held at once. `device` narrows it
    /// to one device's lines.
    func ledgerLines(sourceId: String, pathKeys: [String], device: String? = nil) throws -> [String: [LedgerLine]] {
        try database.reader.read { db in
            var out: [String: [LedgerLine]] = [:]
            for start in stride(from: 0, to: pathKeys.count, by: 500) {
                let chunk = Array(pathKeys[start..<min(start + 500, pathKeys.count)])
                let rows = try Row.fetchAll(db, sql: """
                    SELECT pathKey, device, size, modifiedAt, sha256, recordedAt FROM hash_index_lines
                    WHERE sourceId = ? AND pathKey IN (\(databaseQuestionMarks(count: chunk.count)))\(device == nil ? "" : " AND device = ?")
                    """, arguments: StatementArguments([sourceId] + chunk + (device.map { [$0] } ?? [])))
                for row in rows {
                    let line = LedgerLine(pathKey: row["pathKey"], device: row["device"], size: row["size"],
                                          modifiedAt: row["modifiedAt"], sha256: row["sha256"], recordedAt: row["recordedAt"])
                    out[line.pathKey, default: []].append(line)
                }
            }
            return out
        }
    }

    /// A server file this device hashed itself, for its own ledger segment.
    struct OwnServerHash: Sendable {
        var relativePath: String
        var size: Int64
        var modifiedAt: Int
        var sha256: String
        /// When this device hashed it.
        var hashedAt: Int
        var copyId = ""
        var fileKey = ""
    }

    /// Files of the source this device hashed itself, with a write time —
    /// what its ledger segments may carry.
    /// `unshared`: only those not yet queued for iCloud (§12.3).
    func ownServerHashes(sourceId: String, unshared: Bool = false, limit: Int = .max) throws -> [OwnServerHash] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.copyId, f.fileKey, f.size, f.modifiedAt, f.sha256, f.hashedAt,
                       CASE f.fileKey WHEN 'companion' THEN c.pairedPath ELSE c.relativePath END AS path
                FROM copy_files f JOIN photo_copies c ON c.id = f.copyId
                WHERE c.sourceId = ? AND c.kind = 'server' AND c.missingSince IS NULL
                  AND f.origin = 'hashed' AND f.sha256 IS NOT NULL AND f.size IS NOT NULL AND f.modifiedAt IS NOT NULL
                  \(unshared ? "AND f.sharedAt IS NULL" : "")
                LIMIT ?
                """, arguments: [sourceId, min(limit, Int(Int32.max))]).compactMap { row in
                guard let path: String = row["path"] else { return nil }
                return OwnServerHash(relativePath: path, size: row["size"], modifiedAt: row["modifiedAt"], sha256: row["sha256"],
                                     hashedAt: row["hashedAt"] ?? 0, copyId: row["copyId"], fileKey: row["fileKey"])
            }
        }
    }

    /// These own hashes are queued for the other devices.
    func markShared(_ files: [(copyId: String, fileKey: String)], at now: Date = Date()) throws {
        guard !files.isEmpty else { return }
        let time = Int(now.timeIntervalSince1970)
        try database.writer.write { db in
            for file in files {
                try db.execute(sql: "UPDATE copy_files SET sharedAt = ? WHERE copyId = ? AND fileKey = ?",
                               arguments: [time, file.copyId, file.fileKey])
            }
        }
    }

    // MARK: - Hashes from other devices (FS-19.07 §12.4)

    /// A random check found a hash from `device` wrong at `now`: every hash
    /// it sent up to then is dropped — those files are unchecked again and
    /// hashed here — and remembered, so the same hashes are not taken back
    /// in. Hashes worked out here, or by Backup, stay. Returns how many went.
    @discardableResult
    func distrust(device: String, at now: Date = Date()) throws -> Int {
        try database.writer.write { db in try Self.distrust(db, device: device, at: now) }
    }

    private static func distrust(_ db: Database, device: String, at now: Date) throws -> Int {
        let time = Int(now.timeIntervalSince1970)
        try db.execute(sql: """
            INSERT INTO distrusted_hash_devices (device, since) VALUES (?, ?)
            ON CONFLICT(device) DO UPDATE SET since = MAX(since, excluded.since)
            """, arguments: [device, time])
        // Unchecked again, with a clean slate of tries: hashed here next.
        try db.execute(sql: """
            UPDATE copy_files SET sha256 = NULL, origin = NULL, sharedFrom = NULL, hashedAt = NULL, triedAt = NULL,
                attempts = 0
            WHERE sharedFrom = ? AND origin IN ('shared', 'ledger') AND (hashedAt IS NULL OR hashedAt <= ?)
            """, arguments: [device, time])
        return db.changesCount
    }

    /// A file whose hash another device sent and which makes a photo match
    /// right now — what the random check reads again (§12.4).
    struct AuditFile: Equatable, Sendable {
        var copyId: String
        var fileKey: String
        var sha256: String
        var device: String
        var size: Int64?
        /// `photos` or `server`.
        var kind: String
        var assetId: String?
        var sourceId: String?
        var connectionId: String?
        /// Under the source's root, for a server file.
        var relativePath: String?
    }

    /// The devices this device holds hashes from.
    func auditDevices() throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT sharedFrom FROM copy_files
                WHERE origin IN ('shared', 'ledger') AND sharedFrom IS NOT NULL AND sha256 IS NOT NULL
                ORDER BY sharedFrom
                """)
        }
    }

    /// The files the random check reads at most (§12.4): the bytes it
    /// reads are the price of the check, so the largest files sit out.
    static let auditMaxSize: Int64 = 1 << 30

    /// Up to `limit` of `device`'s hashes, picked from a random point of the
    /// table, among those that match a file on the other side — a Photos
    /// file listed since its photo last changed with a server file of the
    /// same bytes, or the other way round — and that can be read now: Photos
    /// files when `photos`, server files of `sources`.
    func auditSample(device: String, limit: Int, photos: Bool = true, sources: Set<String>? = nil) throws -> [AuditFile] {
        try database.reader.read { db in
            let sourceList = sources.map(Array.init) ?? []
            let sourceFilter = sources == nil ? "" : "AND c.sourceId IN (\(databaseQuestionMarks(count: max(sourceList.count, 1))))"
            func fetch(_ condition: String, _ pivot: Int64, _ take: Int) throws -> [AuditFile] {
                var arguments: StatementArguments = [device, Self.auditMaxSize, photos]
                arguments += StatementArguments(sources == nil ? [] : (sourceList.isEmpty ? [""] : sourceList))
                arguments += [pivot, take]
                return try Row.fetchAll(db, sql: """
                    SELECT f.copyId, f.fileKey, f.sha256, f.sharedFrom, f.size, c.kind, c.photoKitId, c.sourceId,
                           s.connectionId, CASE f.fileKey WHEN 'companion' THEN c.pairedPath ELSE c.relativePath END AS path
                    FROM copy_files f
                    JOIN photo_copies c ON c.id = f.copyId
                    LEFT JOIN sources s ON s.id = c.sourceId
                    LEFT JOIN copy_file_listings l ON l.copyId = c.id
                    LEFT JOIN photo_metadata pm ON pm.assetId = c.photoKitId
                    WHERE f.sharedFrom = ? AND f.origin IN ('shared', 'ledger') AND f.sha256 IS NOT NULL
                      AND f.size IS NOT NULL AND f.size <= ?
                      AND ((? AND c.kind = 'photos' AND c.photoKitId IS NOT NULL AND l.stamp IS pm.modificationDate)
                           OR (c.kind = 'server' AND c.missingSince IS NULL AND s.connectionId IS NOT NULL \(sourceFilter)))
                      AND EXISTS (SELECT 1 FROM copy_files g JOIN photo_copies d ON d.id = g.copyId
                                  WHERE g.sha256 = f.sha256
                                    AND ((c.kind = 'photos' AND d.kind = 'server' AND d.missingSince IS NULL)
                                         OR (c.kind = 'server' AND d.kind = 'photos')))
                      AND f.rowid \(condition) ?
                    ORDER BY f.rowid
                    LIMIT ?
                    """, arguments: arguments).map { row in
                    AuditFile(copyId: row["copyId"], fileKey: row["fileKey"], sha256: row["sha256"], device: row["sharedFrom"],
                              size: row["size"], kind: row["kind"], assetId: row["photoKitId"], sourceId: row["sourceId"],
                              connectionId: row["connectionId"], relativePath: row["path"])
                }
            }
            // A window of candidates from a random row on, wrapping round,
            // then K of them at random: no sort of the whole table.
            let window = max(limit * 20, 200)
            let top = try Int64.fetchOne(db, sql: "SELECT MAX(rowid) FROM copy_files") ?? 0
            let pivot = top > 0 ? Int64.random(in: 0...top) : 0
            var pool = try fetch(">=", pivot, window)
            if pool.count < window { pool += try fetch("<", pivot, window - pool.count) }
            return Array(pool.shuffled().prefix(limit))
        }
    }

    /// The random check read `copyId`'s file as `sha256`, which is not what
    /// `device` sent: the read hash is kept, and every hash `device` sent up
    /// to now is dropped — in one transaction, so a crash cannot keep one
    /// without the other. Returns how many hashes were dropped.
    func recordMismatch(_ sha256: String, copyId: String, fileKey: String, device: String, at now: Date = Date()) throws -> Int {
        let time = Int(now.timeIntervalSince1970)
        return try database.writer.write { db in
            try db.execute(sql: """
                UPDATE copy_files SET sha256 = ?, origin = 'hashed', sharedFrom = NULL, hashedAt = ?, triedAt = ?,
                    lastError = NULL, sharedAt = NULL
                WHERE copyId = ? AND fileKey = ?
                """, arguments: [sha256, time, time, copyId, fileKey])
            return try Self.distrust(db, device: device, at: now)
        }
    }

    /// Whether a hash `device` made at `hashedAt` may be used: never one
    /// from before the device was caught wrong (§12.4).
    /// The time is capped at now, as `saveHash` stores it.
    func accepts(device: String, hashedAt: Date, now: Date = Date()) throws -> Bool {
        try database.reader.read { db in
            guard let since = try Int.fetchOne(db, sql: "SELECT since FROM distrusted_hash_devices WHERE device = ?",
                                               arguments: [device]) else { return true }
            return min(Int(hashedAt.timeIntervalSince1970), Int(now.timeIntervalSince1970)) > since
        }
    }

    /// The sender of a shared hash that came without one: still droppable
    /// as a group.
    static let unknownDevice = "unknown"

    /// A read that failed: counted, kept for the progress line, tried again
    /// on a later pass — it never holds up the files behind it.
    func saveFailure(_ message: String, copyId: String, fileKey: String, at now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE copy_files SET attempts = attempts + 1, lastError = ?, triedAt = ?
                WHERE copyId = ? AND fileKey = ?
                """, arguments: [message, Int(now.timeIntervalSince1970), copyId, fileKey])
        }
    }

    // MARK: - Reading

    func files(copyId: String) throws -> [CopyFile] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM copy_files WHERE copyId = ? ORDER BY fileKey", arguments: [copyId])
                .map(Self.file)
        }
    }

    static func file(_ row: Row) -> CopyFile {
        CopyFile(copyId: row["copyId"], fileKey: row["fileKey"], role: CopyFile.Role(rawValue: row["role"]) ?? .photo,
                 size: row["size"], modifiedAt: row["modifiedAt"], stamp: row["stamp"], sha256: row["sha256"],
                 origin: (row["origin"] as String?).flatMap(CopyFile.Origin.init(rawValue:)), sharedFrom: row["sharedFrom"],
                 attempts: row["attempts"], lastError: row["lastError"], triedAt: row["triedAt"])
    }
}
