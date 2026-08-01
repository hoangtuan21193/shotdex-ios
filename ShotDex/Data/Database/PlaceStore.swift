import Foundation
import GRDB

/// One cell of the library that still needs an address, plus how many photos
/// are waiting on it — the unit of work of the geocoding pass.
struct PendingPlaceCell: Equatable, Sendable {
    var cellKey: String
    /// Cell centre, so every photo in the cell is described by the same point.
    var latitude: Double
    var longitude: Double
    var photoCount: Int
}

/// A cached address for one cell, as stored.
struct CachedPlaceCell: Equatable, Sendable {
    var cellKey: String
    var place: ResolvedPlace
    var searchText: String?
    var localeIdentifier: String
    var resolvedAt: Int?
    var failureCount: Int

    /// Nothing here and no point asking again.
    var isExhausted: Bool { resolvedAt == nil && failureCount >= PlaceStore.maximumFailures }
}

/// Reads and writes where photos were taken.
///
/// Deliberately separate from `MetadataStore`: place columns must **not** be
/// part of `PhotoMetadata`. The indexer upserts whole `PhotoMetadata` records,
/// and a record that carried empty place columns would erase resolved addresses
/// on every re-index — the same way an empty EXIF read once blanked 49_828 rows.
/// Columns absent from the record are left untouched by `upsert`, so keeping
/// them out of the model is the protection.
struct PlaceStore: Sendable {
    let database: AppDatabase

    /// Genuine "the geocoder has nothing here" answers before a cell is retired.
    /// Network failures never count, so being offline cannot exhaust anything.
    static let maximumFailures = 3

    // MARK: Work list

    /// Cells with photos that have coordinates and no address yet, busiest first
    /// so the first minute of geocoding covers the most photos.
    ///
    /// Rows are grouped in SQL by the cell key the pass wrote at index time; rows
    /// that predate it (or whose coordinates arrived later) have a null key and
    /// are handed back with `cellKey` empty for the caller to fill in.
    func pendingCells(limit: Int) throws -> [PendingPlaceCell] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT placeCellKey AS cellKey,
                           AVG(latitude) AS latitude,
                           AVG(longitude) AS longitude,
                           COUNT(*) AS photoCount
                    FROM photo_metadata
                    WHERE latitude IS NOT NULL
                      AND longitude IS NOT NULL
                      AND placeResolvedAt IS NULL
                      AND placeCellKey IS NOT NULL
                    GROUP BY placeCellKey
                    ORDER BY photoCount DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map {
                PendingPlaceCell(
                    cellKey: $0["cellKey"],
                    latitude: $0["latitude"],
                    longitude: $0["longitude"],
                    photoCount: $0["photoCount"]
                )
            }
        }
    }

    /// Assigns cell keys to located rows that have none yet, and returns how many
    /// it stamped. Runs before `pendingCells` so grouping can happen in SQL: the
    /// key is computed in Swift (`PlaceCellKey`) because SQLite has no rounding
    /// helper that would stay bit-identical with it.
    func stampMissingCellKeys(limit: Int) throws -> Int {
        try database.writer.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT assetId, latitude, longitude FROM photo_metadata
                    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
                      AND placeCellKey IS NULL AND placeResolvedAt IS NULL
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            var stamped = 0
            for row in rows {
                let assetId: String = row["assetId"]
                let latitude: Double = row["latitude"]
                let longitude: Double = row["longitude"]
                guard let key = PlaceCellKey.key(latitude: latitude, longitude: longitude) else {
                    // Coordinates that cannot be gridded are marked resolved with
                    // nothing, so the scan does not keep picking them up.
                    try db.execute(
                        sql: "UPDATE photo_metadata SET placeResolvedAt = ? WHERE assetId = ?",
                        arguments: [Int(Date().timeIntervalSince1970), assetId]
                    )
                    continue
                }
                try db.execute(
                    sql: "UPDATE photo_metadata SET placeCellKey = ? WHERE assetId = ?",
                    arguments: [key, assetId]
                )
                stamped += 1
            }
            return stamped
        }
    }

    /// Photos left without an address. Drives the indexing progress line.
    func pendingPhotoCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM photo_metadata
                    WHERE latitude IS NOT NULL AND placeResolvedAt IS NULL
                    """
            ) ?? 0
        }
    }

    // MARK: Cell cache

    func cachedCell(key: String, localeIdentifier: String) throws -> CachedPlaceCell? {
        try database.reader.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM place_cells WHERE cellKey = ? AND localeIdentifier = ?",
                arguments: [key, localeIdentifier]
            ).map(Self.cachedCell(from:))
        }
    }

    /// Records a resolved cell and copies it onto every photo in it.
    func save(
        _ place: ResolvedPlace,
        cellKey: String,
        latitude: Double,
        longitude: Double,
        localeIdentifier: String
    ) throws {
        let searchText = PlaceSearchText.build(from: place)
        let now = Int(Date().timeIntervalSince1970)
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO place_cells
                        (cellKey, latitude, longitude, name, subLocality, locality,
                         adminArea, country, countryCode, address, searchText,
                         localeIdentifier, resolvedAt, failureCount)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(cellKey) DO UPDATE SET
                        latitude = excluded.latitude, longitude = excluded.longitude,
                        name = excluded.name, subLocality = excluded.subLocality,
                        locality = excluded.locality, adminArea = excluded.adminArea,
                        country = excluded.country, countryCode = excluded.countryCode,
                        address = excluded.address, searchText = excluded.searchText,
                        localeIdentifier = excluded.localeIdentifier,
                        resolvedAt = excluded.resolvedAt, failureCount = 0
                    """,
                arguments: [
                    cellKey, latitude, longitude, place.name, place.subLocality,
                    place.locality, place.adminArea, place.country, place.countryCode,
                    place.address, searchText, localeIdentifier, now,
                ]
            )
            try Self.applyCell(db, cellKey: cellKey, place: place, searchText: searchText, at: now)
        }
    }

    /// Records that the geocoder had nothing for this cell. Photos in it are
    /// marked resolved only once the cell is exhausted, so a transient gap in
    /// Apple's data does not permanently label them "no place".
    func recordFailure(cellKey: String, latitude: Double, longitude: Double, localeIdentifier: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO place_cells
                        (cellKey, latitude, longitude, localeIdentifier, failureCount)
                    VALUES (?, ?, ?, ?, 1)
                    ON CONFLICT(cellKey) DO UPDATE SET
                        failureCount = place_cells.failureCount + 1,
                        localeIdentifier = excluded.localeIdentifier
                    """,
                arguments: [cellKey, latitude, longitude, localeIdentifier]
            )
            let failures = try Int.fetchOne(
                db,
                sql: "SELECT failureCount FROM place_cells WHERE cellKey = ?",
                arguments: [cellKey]
            ) ?? 0
            guard failures >= Self.maximumFailures else { return }
            try Self.applyCell(
                db,
                cellKey: cellKey,
                place: ResolvedPlace(),
                searchText: nil,
                at: Int(Date().timeIntervalSince1970)
            )
        }
    }

    /// Copies an already-cached cell onto the photos waiting on it — the path
    /// taken when a new photo lands somewhere the library has been before, which
    /// needs no network at all.
    func applyCached(_ cached: CachedPlaceCell) throws {
        guard cached.resolvedAt != nil || cached.isExhausted else { return }
        try database.writer.write { db in
            try Self.applyCell(
                db,
                cellKey: cached.cellKey,
                place: cached.place,
                searchText: cached.searchText,
                at: cached.resolvedAt ?? Int(Date().timeIntervalSince1970)
            )
        }
    }

    private static func applyCell(
        _ db: Database,
        cellKey: String,
        place: ResolvedPlace,
        searchText: String?,
        at timestamp: Int
    ) throws {
        try db.execute(
            sql: """
                UPDATE photo_metadata SET
                    placeName = ?, placeSubLocality = ?, placeLocality = ?,
                    placeAdminArea = ?, placeCountry = ?, placeCountryCode = ?,
                    placeAddress = ?, placeSearchText = ?, placeResolvedAt = ?
                WHERE placeCellKey = ?
                """,
            arguments: [
                place.name, place.subLocality, place.locality, place.adminArea,
                place.country, place.countryCode, place.address, searchText,
                timestamp, cellKey,
            ]
        )
    }

    // MARK: Reads for the UI

    /// The stored address of one photo, for the metadata panel — which can then
    /// show a place with no network and no geocoding round trip.
    func place(assetId: String) throws -> ResolvedPlace? {
        try database.reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT placeName, placeSubLocality, placeLocality, placeAdminArea,
                           placeCountry, placeCountryCode, placeAddress
                    FROM photo_metadata WHERE assetId = ?
                    """,
                arguments: [assetId]
            ) else { return nil }
            let place = ResolvedPlace(
                name: row["placeName"],
                subLocality: row["placeSubLocality"],
                locality: row["placeLocality"],
                adminArea: row["placeAdminArea"],
                country: row["placeCountry"],
                countryCode: row["placeCountryCode"],
                address: row["placeAddress"]
            )
            return place.isEmpty ? nil : place
        }
    }

    /// Clears every resolved address, keeping the cell cache. Used when the
    /// display language changes — the coordinates are still right, the words are
    /// not — and by Settings → Clear local metadata index.
    func clearResolvedPlaces() throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE photo_metadata SET
                        placeName = NULL, placeSubLocality = NULL, placeLocality = NULL,
                        placeAdminArea = NULL, placeCountry = NULL, placeCountryCode = NULL,
                        placeAddress = NULL, placeSearchText = NULL, placeResolvedAt = NULL
                    """
            )
        }
    }

    private static func cachedCell(from row: Row) -> CachedPlaceCell {
        CachedPlaceCell(
            cellKey: row["cellKey"],
            place: ResolvedPlace(
                name: row["name"],
                subLocality: row["subLocality"],
                locality: row["locality"],
                adminArea: row["adminArea"],
                country: row["country"],
                countryCode: row["countryCode"],
                address: row["address"]
            ),
            searchText: row["searchText"],
            localeIdentifier: row["localeIdentifier"],
            resolvedAt: row["resolvedAt"],
            failureCount: row["failureCount"]
        )
    }
}
