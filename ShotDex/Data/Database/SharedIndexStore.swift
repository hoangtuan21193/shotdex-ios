import CryptoKit
import Foundation
import GRDB

/// One file read as the shared index stores it, keyed by iCloud identifier.
struct SharedExifRecord: Equatable, Sendable {
    var cloudIdentifier: String
    var modificationDate: Int?
    var exif: RawExif
}

/// One resolved place cell as it travels between devices — the `place_cells`
/// row minus the local failure bookkeeping.
struct SharedPlaceCell: Equatable, Sendable {
    var cellKey: String
    var latitude: Double
    var longitude: Double
    var place: ResolvedPlace
    var searchText: String?
    var localeIdentifier: String
    var resolvedAt: Int
}

/// Reads and writes the shared index tables (`shared_exif`, `cloud_outbox`;
/// migration v45). Local reads are queued for upload; rows pulled from
/// iCloud are not. Nothing here talks to the network — `IndexShareService`
/// does.
/// A Photos file's SHA-256 one device worked out (FS-19.07 §12.3), keyed by
/// iCloud identifier and resource key, with the asset's modification date
/// it was hashed at.
struct SharedPhotoHash: Equatable, Sendable {
    var cloudId: String
    var fileKey: String
    var assetModified: Int?
    var size: Int64?
    var sha256: String
    var device: String
    var hashedAt: Int

    var recordName: String { SharedIndexStore.recordName("photo", device, cloudId, fileKey) }
}

/// A server file's SHA-256 one device worked out, keyed by the server's
/// identity (`ServerIdentity.key`) and the path on the server.
struct SharedServerHash: Equatable, Sendable {
    var serverKey: String
    var pathKey: String
    var size: Int64
    var modifiedAt: Int?
    var sha256: String
    var device: String
    var hashedAt: Int

    var recordName: String { SharedIndexStore.recordName("server", device, serverKey, pathKey) }
}

struct SharedIndexStore: Sendable {
    static let photoExifType = "PhotoExif"
    static let placeCellType = "PlaceCell"
    static let photoHashType = "PhotoFileHash"
    static let serverHashType = "ServerFileHash"

    /// A record name under CloudKit's 255-byte limit whatever the path:
    /// the SHA-256 of its parts.
    static func recordName(_ parts: String...) -> String {
        FileChecksum.hex(SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)))
    }

    let database: AppDatabase

    // MARK: Photo EXIF

    /// Stores what this device read and queues it for upload. A row already
    /// holding the same date and EXIF is left alone and not queued again, so
    /// re-reading a library does not re-upload it.
    func saveLocal(_ records: [SharedExifRecord], now: Date = Date()) throws {
        guard !records.isEmpty else { return }
        let timestamp = Int(now.timeIntervalSince1970)
        // Sorted keys: the unchanged check below compares bytes, and an
        // unsorted encoder is free to order keys differently each time.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try database.writer.write { db in
            for record in records {
                let payload = try encoder.encode(record.exif)
                if let row = try Row.fetchOne(
                    db,
                    sql: "SELECT modificationDate, payload FROM shared_exif WHERE cloudIdentifier = ?",
                    arguments: [record.cloudIdentifier]
                ), row["modificationDate"] as Int? == record.modificationDate,
                   (row["payload"] as Data?) == payload {
                    continue
                }
                try Self.upsert(db, record: record, payload: payload, origin: "local", at: timestamp)
                try Self.enqueue(db, recordType: Self.photoExifType, recordName: record.cloudIdentifier, at: timestamp)
            }
        }
    }

    /// Stores rows pulled from iCloud. A row this device read for a newer
    /// modification date wins over an older one from elsewhere.
    @discardableResult
    func saveRemote(_ records: [SharedExifRecord], now: Date = Date()) throws -> Int {
        guard !records.isEmpty else { return 0 }
        let timestamp = Int(now.timeIntervalSince1970)
        let encoder = JSONEncoder()
        return try database.writer.write { db in
            var written = 0
            for record in records {
                if let existing = try Int.fetchOne(
                    db,
                    sql: "SELECT modificationDate FROM shared_exif WHERE cloudIdentifier = ?",
                    arguments: [record.cloudIdentifier]
                ), let incoming = record.modificationDate, existing > incoming {
                    continue
                }
                try Self.upsert(db, record: record, payload: try encoder.encode(record.exif), origin: "cloud", at: timestamp)
                written += 1
            }
            return written
        }
    }

    /// Stored EXIF for these iCloud identifiers, with the date each was read at.
    func exif(cloudIdentifiers: [String]) throws -> [String: SharedExifRecord] {
        guard !cloudIdentifiers.isEmpty else { return [:] }
        let decoder = JSONDecoder()
        return try database.reader.read { db in
            var result: [String: SharedExifRecord] = [:]
            // SQLite's default variable limit is 32766; batches are 200.
            for chunk in stride(from: 0, to: cloudIdentifiers.count, by: 500) {
                let slice = Array(cloudIdentifiers[chunk..<min(chunk + 500, cloudIdentifiers.count)])
                let placeholders = Array(repeating: "?", count: slice.count).joined(separator: ",")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT cloudIdentifier, modificationDate, payload FROM shared_exif WHERE cloudIdentifier IN (\(placeholders))",
                    arguments: StatementArguments(slice)
                )
                for row in rows {
                    let id: String = row["cloudIdentifier"]
                    // One unreadable row must not cost the batch its reuse.
                    guard let data = row["payload"] as Data?,
                          let exif = try? decoder.decode(RawExif.self, from: data)
                    else { continue }
                    result[id] = SharedExifRecord(cloudIdentifier: id, modificationDate: row["modificationDate"], exif: exif)
                }
            }
            return result
        }
    }

    // MARK: Place cells

    /// Resolved cells by key, for upload.
    func placeCells(keys: [String]) throws -> [SharedPlaceCell] {
        guard !keys.isEmpty else { return [] }
        return try database.reader.read { db in
            let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM place_cells WHERE resolvedAt IS NOT NULL AND cellKey IN (\(placeholders))",
                arguments: StatementArguments(keys)
            ).map { row in
                SharedPlaceCell(
                    cellKey: row["cellKey"],
                    latitude: row["latitude"],
                    longitude: row["longitude"],
                    place: ResolvedPlace(
                        name: row["name"], subLocality: row["subLocality"], locality: row["locality"],
                        adminArea: row["adminArea"], country: row["country"], countryCode: row["countryCode"],
                        address: row["address"]
                    ),
                    searchText: row["searchText"],
                    localeIdentifier: row["localeIdentifier"],
                    resolvedAt: row["resolvedAt"]
                )
            }
        }
    }

    /// Stores cells pulled from iCloud and copies each onto the photos in it.
    /// A cell this device already resolved keeps its own answer; a cell it
    /// only failed on takes the remote one.
    @discardableResult
    func saveRemote(_ cells: [SharedPlaceCell]) throws -> Int {
        guard !cells.isEmpty else { return 0 }
        return try database.writer.write { db in
            var written = 0
            for cell in cells {
                let resolved = try Bool.fetchOne(
                    db,
                    sql: "SELECT resolvedAt IS NOT NULL FROM place_cells WHERE cellKey = ?",
                    arguments: [cell.cellKey]
                ) ?? false
                guard !resolved else { continue }
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO place_cells
                            (cellKey, latitude, longitude, name, subLocality, locality,
                             adminArea, country, countryCode, address, searchText,
                             localeIdentifier, resolvedAt, failureCount)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                        """,
                    arguments: [
                        cell.cellKey, cell.latitude, cell.longitude, cell.place.name,
                        cell.place.subLocality, cell.place.locality, cell.place.adminArea,
                        cell.place.country, cell.place.countryCode, cell.place.address,
                        cell.searchText, cell.localeIdentifier, cell.resolvedAt,
                    ]
                )
                try PlaceStore.applyCell(db, cellKey: cell.cellKey, place: cell.place, searchText: cell.searchText, at: cell.resolvedAt)
                written += 1
            }
            return written
        }
    }

    // MARK: Outbox

    // MARK: File hashes (FS-19.07 §12.3)

    /// This device's hashes, queued for upload — a row already holding the
    /// same hash is not queued again.
    func saveLocal(photoHashes: [SharedPhotoHash], serverHashes: [SharedServerHash], now: Date = Date()) throws {
        guard !photoHashes.isEmpty || !serverHashes.isEmpty else { return }
        let timestamp = Int(now.timeIntervalSince1970)
        try database.writer.write { db in
            for hash in photoHashes {
                // Unchanged in every key another device matches on: not sent again.
                if let kept = try Row.fetchOne(db, sql: "SELECT sha256, assetModified, size FROM shared_photo_hashes WHERE recordName = ?",
                                               arguments: [hash.recordName]),
                   kept["sha256"] as String? == hash.sha256.lowercased(), kept["assetModified"] as Int? == hash.assetModified,
                   kept["size"] as Int64? == hash.size {
                    continue
                }
                try Self.upsert(db, hash, origin: "local")
                try Self.enqueue(db, recordType: Self.photoHashType, recordName: hash.recordName, at: timestamp)
            }
            for hash in serverHashes {
                if let kept = try Row.fetchOne(db, sql: "SELECT sha256, modifiedAt, size FROM shared_server_hashes WHERE recordName = ?",
                                               arguments: [hash.recordName]),
                   kept["sha256"] as String? == hash.sha256.lowercased(), kept["modifiedAt"] as Int? == hash.modifiedAt,
                   kept["size"] as Int64? == hash.size {
                    continue
                }
                try Self.upsert(db, hash, origin: "local")
                try Self.enqueue(db, recordType: Self.serverHashType, recordName: hash.recordName, at: timestamp)
            }
        }
    }

    /// Hashes pulled from iCloud. One of this device's own rows is never
    /// replaced by a pulled copy of itself.
    func saveRemote(photoHashes: [SharedPhotoHash], serverHashes: [SharedServerHash]) throws {
        guard !photoHashes.isEmpty || !serverHashes.isEmpty else { return }
        try database.writer.write { db in
            for hash in photoHashes { try Self.upsert(db, hash, origin: "cloud") }
            for hash in serverHashes { try Self.upsert(db, hash, origin: "cloud") }
        }
    }

    /// The names devices sent with their hashes; the latest wins.
    func saveDeviceNames(_ names: [String: String]) throws {
        guard !names.isEmpty else { return }
        try database.writer.write { db in
            for (device, name) in names where !name.isEmpty {
                try db.execute(sql: """
                    INSERT INTO hash_device_names (device, name) VALUES (?, ?)
                    ON CONFLICT(device) DO UPDATE SET name = excluded.name
                    """, arguments: [device, name])
            }
        }
    }

    /// Names by device, for those that sent one.
    func deviceNames(_ devices: [String]) throws -> [String: String] {
        guard !devices.isEmpty else { return [:] }
        return try database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: """
                SELECT device, name FROM hash_device_names WHERE device IN (\(databaseQuestionMarks(count: devices.count)))
                """, arguments: StatementArguments(devices)).map { ($0["device"] as String, $0["name"] as String) })
        }
    }

    /// Other devices' hashes of these photos' files.
    func remotePhotoHashes(cloudIds: [String]) throws -> [SharedPhotoHash] {
        try database.reader.read { db in
            var out: [SharedPhotoHash] = []
            for start in stride(from: 0, to: cloudIds.count, by: 500) {
                let chunk = Array(cloudIds[start..<min(start + 500, cloudIds.count)])
                out += try Row.fetchAll(db, sql: """
                    SELECT * FROM shared_photo_hashes WHERE origin = 'cloud' AND cloudId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(chunk)).map(Self.photoHash)
            }
            return out
        }
    }

    /// Other devices' hashes of these paths on the server.
    func remoteServerHashes(serverKey: String, pathKeys: [String]) throws -> [SharedServerHash] {
        try database.reader.read { db in
            var out: [SharedServerHash] = []
            for start in stride(from: 0, to: pathKeys.count, by: 500) {
                let chunk = Array(pathKeys[start..<min(start + 500, pathKeys.count)])
                out += try Row.fetchAll(db, sql: """
                    SELECT * FROM shared_server_hashes WHERE origin = 'cloud' AND serverKey = ?
                      AND pathKey IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([serverKey] + chunk)).map(Self.serverHash)
            }
            return out
        }
    }

    /// This device's queued rows, by record name, for the upload.
    func localHashes(recordNames: [String]) throws -> (photos: [SharedPhotoHash], servers: [SharedServerHash]) {
        guard !recordNames.isEmpty else { return ([], []) }
        return try database.reader.read { db in
            let marks = databaseQuestionMarks(count: recordNames.count)
            let photos = try Row.fetchAll(db, sql: "SELECT * FROM shared_photo_hashes WHERE recordName IN (\(marks))",
                                          arguments: StatementArguments(recordNames)).map(Self.photoHash)
            let servers = try Row.fetchAll(db, sql: "SELECT * FROM shared_server_hashes WHERE recordName IN (\(marks))",
                                           arguments: StatementArguments(recordNames)).map(Self.serverHash)
            return (photos, servers)
        }
    }

    private static func upsert(_ db: Database, _ hash: SharedPhotoHash, origin: String) throws {
        try db.execute(sql: """
            INSERT INTO shared_photo_hashes (recordName, cloudId, fileKey, assetModified, size, sha256, device, hashedAt, origin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recordName) DO UPDATE SET assetModified = excluded.assetModified, size = excluded.size,
                sha256 = excluded.sha256, hashedAt = excluded.hashedAt
            WHERE excluded.origin = 'local' OR shared_photo_hashes.origin = 'cloud'
            """, arguments: [hash.recordName, hash.cloudId, hash.fileKey, hash.assetModified, hash.size, hash.sha256.lowercased(),
                             hash.device, hash.hashedAt, origin])
    }

    private static func upsert(_ db: Database, _ hash: SharedServerHash, origin: String) throws {
        try db.execute(sql: """
            INSERT INTO shared_server_hashes (recordName, serverKey, pathKey, size, modifiedAt, sha256, device, hashedAt, origin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recordName) DO UPDATE SET size = excluded.size, modifiedAt = excluded.modifiedAt,
                sha256 = excluded.sha256, hashedAt = excluded.hashedAt
            WHERE excluded.origin = 'local' OR shared_server_hashes.origin = 'cloud'
            """, arguments: [hash.recordName, hash.serverKey, hash.pathKey, hash.size, hash.modifiedAt, hash.sha256.lowercased(),
                             hash.device, hash.hashedAt, origin])
    }

    private static func photoHash(_ row: Row) -> SharedPhotoHash {
        SharedPhotoHash(cloudId: row["cloudId"], fileKey: row["fileKey"], assetModified: row["assetModified"], size: row["size"],
                        sha256: row["sha256"], device: row["device"], hashedAt: row["hashedAt"])
    }

    private static func serverHash(_ row: Row) -> SharedServerHash {
        SharedServerHash(serverKey: row["serverKey"], pathKey: row["pathKey"], size: row["size"], modifiedAt: row["modifiedAt"],
                         sha256: row["sha256"], device: row["device"], hashedAt: row["hashedAt"])
    }

    struct OutboxItem: Equatable, Sendable {
        var recordType: String
        var recordName: String
    }

    func outbox(limit: Int) throws -> [OutboxItem] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT recordType, recordName FROM cloud_outbox ORDER BY queuedAt LIMIT ?",
                arguments: [limit]
            ).map { OutboxItem(recordType: $0["recordType"], recordName: $0["recordName"]) }
        }
    }

    func outboxCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cloud_outbox") ?? 0
        }
    }

    func removeFromOutbox(_ items: [OutboxItem]) throws {
        guard !items.isEmpty else { return }
        try database.writer.write { db in
            for item in items {
                try db.execute(
                    sql: "DELETE FROM cloud_outbox WHERE recordType = ? AND recordName = ?",
                    arguments: [item.recordType, item.recordName]
                )
            }
        }
    }

    static func enqueue(_ db: Database, recordType: String, recordName: String, at timestamp: Int) throws {
        try db.execute(
            sql: """
                INSERT INTO cloud_outbox (recordType, recordName, queuedAt) VALUES (?, ?, ?)
                ON CONFLICT(recordType, recordName) DO UPDATE SET queuedAt = excluded.queuedAt
                """,
            arguments: [recordType, recordName, timestamp]
        )
    }

    private static func upsert(_ db: Database, record: SharedExifRecord, payload: Data, origin: String, at timestamp: Int) throws {
        try db.execute(
            sql: """
                INSERT INTO shared_exif (cloudIdentifier, modificationDate, payload, origin, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(cloudIdentifier) DO UPDATE SET
                    modificationDate = excluded.modificationDate, payload = excluded.payload,
                    origin = excluded.origin, updatedAt = excluded.updatedAt
                """,
            arguments: [record.cloudIdentifier, record.modificationDate, payload, origin, timestamp]
        )
    }
}
