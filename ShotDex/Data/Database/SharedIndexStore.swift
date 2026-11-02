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
struct SharedIndexStore: Sendable {
    static let photoExifType = "PhotoExif"
    static let placeCellType = "PlaceCell"

    let database: AppDatabase

    // MARK: Photo EXIF

    /// Stores what this device read and queues it for upload. A row already
    /// holding the same date and EXIF is left alone and not queued again, so
    /// re-reading a library does not re-upload it.
    func saveLocal(_ records: [SharedExifRecord], now: Date = Date()) throws {
        guard !records.isEmpty else { return }
        let timestamp = Int(now.timeIntervalSince1970)
        let encoder = JSONEncoder()
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
