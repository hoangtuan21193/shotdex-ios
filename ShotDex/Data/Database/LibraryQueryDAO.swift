import Foundation
import GRDB

/// Read-side queries for the Library grid: filter, search, sort.
struct LibraryQueryDAO: Sendable {
    let database: AppDatabase

    /// The whole filtered library as slim grid rows, in display sort order.
    /// No paging — the grid virtualizes rendering over the full list.
    /// Async so the (potentially 100k-row) decode runs on GRDB's reader
    /// pool, not the main thread.
    func gridItems(
        matching criteria: FilterCriteria,
        sort: SortOption
    ) async throws -> [LibraryGridItem] {
        let (whereSQL, arguments) = Self.whereClause(for: criteria)
        let sql = """
            SELECT assetId, creationDate, iso, aperture, shutterSpeedDisplay,
                   focalLength, equivalentFocalLength
            FROM photo_metadata
            \(whereSQL)
            ORDER BY \(Self.orderClause(for: sort))
            """
        return try await database.reader.read { db in
            try LibraryGridItem.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Full row for the detail viewer / metadata panel, fetched on demand.
    func metadata(assetId: String) throws -> PhotoMetadata? {
        try database.reader.read { db in
            try PhotoMetadata.fetchOne(db, key: assetId)
        }
    }

    /// Batch full rows (Compare screen), keyed by asset id.
    func metadata(assetIds: [String]) throws -> [String: PhotoMetadata] {
        guard !assetIds.isEmpty else { return [:] }
        let rows = try database.reader.read { db in
            try PhotoMetadata.fetchAll(db, keys: assetIds)
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.assetId, $0) })
    }

    /// Number of photos matching the criteria (for the filter chips bar).
    func count(matching criteria: FilterCriteria) throws -> Int {
        let (whereSQL, arguments) = Self.whereClause(for: criteria)
        let sql = "SELECT COUNT(*) FROM photo_metadata \(whereSQL)"
        return try database.reader.read { db in
            try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    /// Distinct normalized camera manufacturers, for the filter sheet.
    func distinctCameraBrands() throws -> [String] {
        try distinctValues(column: "normalizedCameraManufacturer")
    }

    /// Distinct normalized camera bodies, for the filter sheet and autosuggest.
    func distinctCameraBodies() throws -> [String] {
        try distinctValues(column: "normalizedCameraModel")
    }

    /// Distinct normalized lenses, for the filter sheet and autosuggest.
    func distinctLenses() throws -> [String] {
        try distinctValues(column: "normalizedLensModel")
    }

    private func distinctValues(column: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT \(column) FROM photo_metadata
                    WHERE \(column) IS NOT NULL AND \(column) != ''
                    ORDER BY \(column) COLLATE NOCASE
                    """
            )
        }
    }

    // MARK: SQL construction

    static func whereClause(for criteria: FilterCriteria) -> (sql: String, arguments: StatementArguments) {
        var conditions: [String] = []
        var values: [DatabaseValueConvertible] = []

        func addSet(_ set: Set<String>, column: String) {
            guard !set.isEmpty else { return }
            let placeholders = Array(repeating: "?", count: set.count).joined(separator: ", ")
            conditions.append("\(column) IN (\(placeholders))")
            values.append(contentsOf: set.sorted())
        }

        func addRange(_ range: NumericRangeFilter, column: String) {
            if let lower = range.lowerBound {
                conditions.append("\(column) >= ?")
                values.append(lower)
            }
            if let upper = range.upperBound {
                conditions.append("\(column) <= ?")
                values.append(upper)
            }
        }

        addSet(criteria.cameraBrands, column: "normalizedCameraManufacturer")
        addSet(criteria.cameraBodies, column: "normalizedCameraModel")
        addSet(criteria.lenses, column: "normalizedLensModel")
        addSet(Set(criteria.sensorFormats.map(\.rawValue)), column: "sensorFormat")

        addRange(criteria.isoRange, column: "iso")
        addRange(criteria.shutterRange, column: "shutterSpeedSeconds")
        addRange(criteria.apertureRange, column: "aperture")

        let focalColumn = criteria.focalLengthMode == .equivalent
            ? "equivalentFocalLength"
            : "focalLength"
        addRange(criteria.focalRange, column: focalColumn)

        if criteria.favoritesOnly {
            conditions.append("isFavorite = 1")
        }

        if let text = criteria.searchText, !text.isEmpty {
            let parsed = SearchParser.parse(text)

            if let iso = parsed.iso {
                conditions.append("iso = ?")
                values.append(iso)
            }
            if let aperture = parsed.aperture {
                conditions.append("aperture BETWEEN ? AND ?")
                values.append(contentsOf: [aperture - 0.05, aperture + 0.05])
            }
            if let shutter = parsed.shutterSeconds {
                conditions.append("shutterSpeedSeconds BETWEEN ? AND ?")
                values.append(contentsOf: [shutter * 0.9, shutter * 1.1])
            }
            if let focal = parsed.focalLength {
                conditions.append("(focalLength BETWEEN ? AND ? OR equivalentFocalLength BETWEEN ? AND ?)")
                values.append(contentsOf: [focal - 0.5, focal + 0.5, focal - 0.5, focal + 0.5])
            }
            if let format = parsed.sensorFormat {
                conditions.append("sensorFormat = ?")
                values.append(format.rawValue)
            }
            for term in parsed.freeTextTerms {
                conditions.append("""
                    (cameraModel LIKE ? COLLATE NOCASE
                     OR lensModel LIKE ? COLLATE NOCASE
                     OR normalizedCameraModel LIKE ? COLLATE NOCASE
                     OR normalizedLensModel LIKE ? COLLATE NOCASE
                     OR normalizedCameraManufacturer LIKE ? COLLATE NOCASE
                     OR originalFilename LIKE ? COLLATE NOCASE)
                    """)
                let pattern = "%\(term)%"
                values.append(contentsOf: [pattern, pattern, pattern, pattern, pattern, pattern])
            }
            // Bare numbers OR into ISO / focal length / device names.
            for number in parsed.bareNumbers {
                conditions.append("""
                    (iso = ?
                     OR CAST(focalLength AS INTEGER) = ?
                     OR CAST(equivalentFocalLength AS INTEGER) = ?
                     OR cameraModel LIKE ? COLLATE NOCASE
                     OR lensModel LIKE ? COLLATE NOCASE
                     OR originalFilename LIKE ? COLLATE NOCASE)
                    """)
                let intValue = Int(number)
                let pattern = "%\(number == number.rounded() ? String(intValue) : String(number))%"
                values.append(contentsOf: [intValue, intValue, intValue, pattern, pattern, pattern] as [DatabaseValueConvertible])
            }
        }

        let sql = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return (sql, StatementArguments(values))
    }

    /// Every clause ends with the `assetId` primary key so the ordering is
    /// total — ties would otherwise make the display order nondeterministic
    /// across reloads.
    static func orderClause(for sort: SortOption) -> String {
        let clause = switch sort {
        case .dateTakenNewest: "creationDate DESC NULLS LAST"
        case .dateTakenOldest: "creationDate ASC NULLS LAST"
        case .isoDescending: "iso DESC NULLS LAST, creationDate DESC NULLS LAST"
        case .isoAscending: "iso ASC NULLS LAST, creationDate DESC NULLS LAST"
        case .focalLengthDescending: "focalLength DESC NULLS LAST, creationDate DESC NULLS LAST"
        case .focalLengthAscending: "focalLength ASC NULLS LAST, creationDate DESC NULLS LAST"
        case .equivalentFocalLengthDescending: "equivalentFocalLength DESC NULLS LAST, creationDate DESC NULLS LAST"
        case .equivalentFocalLengthAscending: "equivalentFocalLength ASC NULLS LAST, creationDate DESC NULLS LAST"
        case .apertureAscending: "aperture ASC NULLS LAST, creationDate DESC NULLS LAST"
        case .apertureDescending: "aperture DESC NULLS LAST, creationDate DESC NULLS LAST"
        case .shutterSpeedFastest: "shutterSpeedSeconds ASC NULLS LAST, creationDate DESC NULLS LAST"
        case .shutterSpeedSlowest: "shutterSpeedSeconds DESC NULLS LAST, creationDate DESC NULLS LAST"
        }
        return clause + ", assetId ASC"
    }
}
