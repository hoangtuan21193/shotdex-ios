import Foundation
import GRDB

/// What a common-photos scan read of one file (FS-19.08 §6c): its SHA-256
/// and its capture key, either of which may be missing. Good while the file
/// keeps its size and write time; the write time never says two files are
/// the same, only that this one did not change.
struct CommonPhotosScanRecord: Equatable, Sendable {
    var path: String
    var size: Int64
    var modifiedAt: Int
    var sha256: String?
    /// Empty when the head was read and held no capture key: not read
    /// again either.
    var captureKey: String?
}

/// Reads and writes `common_photo_scan_records`.
struct CommonPhotosScanRecords: Sendable {
    let database: AppDatabase

    /// The records of these paths on the connection, by path.
    func records(connectionId: String, paths: [String]) throws -> [String: CommonPhotosScanRecord] {
        guard !paths.isEmpty else { return [:] }
        return try database.reader.read { db in
            var out: [String: CommonPhotosScanRecord] = [:]
            for start in stride(from: 0, to: paths.count, by: 500) {
                let chunk = Array(paths[start..<min(start + 500, paths.count)])
                for row in try Row.fetchAll(db, sql: """
                    SELECT path, size, modifiedAt, sha256, captureKey FROM common_photo_scan_records
                    WHERE connectionId = ? AND path IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([connectionId] + chunk)) {
                    let record = CommonPhotosScanRecord(path: row["path"], size: row["size"], modifiedAt: row["modifiedAt"],
                                                        sha256: row["sha256"], captureKey: row["captureKey"])
                    out[record.path] = record
                }
            }
            return out
        }
    }

    /// Records no scan has touched for this long go: a folder nobody scans
    /// again should not be remembered for ever.
    static let keptFor: TimeInterval = 180 * 24 * 3600

    /// Saves what was read, a thousand at a time so the database's one
    /// writer is not held for a whole scan. A record of the same size and
    /// write time keeps what it had and gains what is new; a different size
    /// or write time is another file, and replaces it.
    func save(connectionId: String, _ records: [CommonPhotosScanRecord], at now: Date = Date()) throws {
        guard !records.isEmpty else { return }
        let time = Int(now.timeIntervalSince1970)
        for start in stride(from: 0, to: records.count, by: 1_000) {
            try database.writer.write { db in
                for record in records[start..<min(start + 1_000, records.count)] {
                    try db.execute(sql: """
                        INSERT INTO common_photo_scan_records (connectionId, path, size, modifiedAt, sha256, captureKey, readAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(connectionId, path) DO UPDATE SET
                            sha256 = CASE WHEN size = excluded.size AND modifiedAt = excluded.modifiedAt
                                          THEN COALESCE(excluded.sha256, sha256) ELSE excluded.sha256 END,
                            captureKey = CASE WHEN size = excluded.size AND modifiedAt = excluded.modifiedAt
                                              THEN COALESCE(excluded.captureKey, captureKey) ELSE excluded.captureKey END,
                            size = excluded.size, modifiedAt = excluded.modifiedAt, readAt = excluded.readAt
                        """, arguments: [connectionId, record.path, record.size, record.modifiedAt,
                                         record.sha256?.lowercased(), record.captureKey, time])
                }
            }
        }
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM common_photo_scan_records WHERE readAt < ?",
                           arguments: [time - Int(Self.keptFor)])
        }
    }

    /// Forgets the files under `folder` a listing no longer shows. The
    /// paths under it are the range from `folder/` to `folder0` (`0` comes
    /// right after `/`), exact case, on the primary key.
    @discardableResult
    func prune(connectionId: String, under folder: String, keeping listed: Set<String>) throws -> Int {
        let prefix = ServerUploadPath.normalizedFolder(folder)
        return try database.writer.write { db in
            let known = prefix.isEmpty
                ? try String.fetchAll(db, sql: "SELECT path FROM common_photo_scan_records WHERE connectionId = ?",
                                      arguments: [connectionId])
                : try String.fetchAll(db, sql: """
                    SELECT path FROM common_photo_scan_records WHERE connectionId = ? AND path >= ? AND path < ?
                    """, arguments: [connectionId, prefix + "/", prefix + "0"])
            let gone = known.filter { !listed.contains($0) }
            for start in stride(from: 0, to: gone.count, by: 500) {
                let chunk = Array(gone[start..<min(start + 500, gone.count)])
                try db.execute(sql: """
                    DELETE FROM common_photo_scan_records
                    WHERE connectionId = ? AND path IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([connectionId] + chunk))
            }
            return gone.count
        }
    }

    /// The connection is gone: so is what was read through it.
    static func forget(connectionId: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM common_photo_scan_records WHERE connectionId = ?", arguments: [connectionId])
    }
}
