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
    }

    var copyId: String
    var fileKey: String
    var role: Role
    var size: Int64?
    var modifiedAt: Int?
    var stamp: String?
    var sha256: String?
    var origin: Origin?
    var attempts = 0
    var lastError: String?
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
    let database: AppDatabase

    // MARK: - Photos

    /// Photos copies whose files were never listed, or listed before the
    /// asset last changed — newest photo first (FS-19.07 §4).
    func photosCopiesNeedingListing(limit: Int) throws -> [(copyId: String, assetId: String, stamp: Int?)] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoKitId, m.modificationDate FROM photo_copies c
                JOIN photo_metadata m ON m.assetId = c.photoKitId
                LEFT JOIN copy_file_listings l ON l.copyId = c.id
                WHERE c.kind = 'photos' AND c.photoKitId IS NOT NULL
                  AND (l.copyId IS NULL OR l.stamp IS NOT m.modificationDate)
                ORDER BY m.creationDate DESC, c.id LIMIT ?
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
                UPDATE copy_files SET sha256 = m.sha256, origin = 'backup', hashedAt = ?, lastError = NULL
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
                 origin: (row["origin"] as String?).flatMap(CopyFile.Origin.init(rawValue:)),
                 attempts: row["attempts"], lastError: row["lastError"])
    }
}
