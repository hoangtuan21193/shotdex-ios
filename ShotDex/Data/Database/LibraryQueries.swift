import Foundation
import GRDB

/// Read-side queries for the Library grid: filter, search, sort.
struct LibraryQueries: Sendable {
    let database: AppDatabase

    /// The whole filtered library as slim grid rows, in display sort order.
    /// No paging — the grid virtualizes rendering over the full list.
    /// Async so the (potentially 100k-row) decode runs on GRDB's reader
    /// pool, not the main thread. `limit` serves the Library first-paint
    /// slice; nil (the default) returns everything.
    func gridItems(
        matching criteria: FilterCriteria,
        sort: SortOption,
        limit: Int? = nil
    ) async throws -> [LibraryGridItem] {
        let (whereSQL, arguments) = Self.whereClause(for: criteria)
        let sql = """
            SELECT assetId, creationDate, mediaType, originalFilename,
                   iso, aperture, shutterSpeedDisplay,
                   focalLength, equivalentFocalLength, width, height, fileSize
            FROM photo_metadata
            \(whereSQL)
            ORDER BY \(Self.orderClause(for: sort))
            \(limit.map { "LIMIT \($0)" } ?? "")
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

    /// Number of photos matching the criteria (for the filter tokens bar).
    func count(matching criteria: FilterCriteria) throws -> Int {
        let (whereSQL, arguments) = Self.whereClause(for: criteria)
        let sql = "SELECT COUNT(*) FROM photo_metadata \(whereSQL)"
        return try database.reader.read { db in
            try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    // MARK: Smart-album rule queries

    /// Grid rows for a smart album's saved rule query (see `gridItems(matching
    /// criteria:)` — same SELECT, but the WHERE is compiled from rules with the
    /// album's `all`/`any` match mode).
    func gridItems(
        matching query: SmartAlbumQuery,
        sort: SortOption,
        limit: Int? = nil
    ) async throws -> [LibraryGridItem] {
        let (whereSQL, arguments) = Self.whereClause(for: query)
        let sql = """
            SELECT assetId, creationDate, mediaType, originalFilename,
                   iso, aperture, shutterSpeedDisplay,
                   focalLength, equivalentFocalLength, width, height, fileSize
            FROM photo_metadata
            \(whereSQL)
            ORDER BY \(Self.orderClause(for: sort))
            \(limit.map { "LIMIT \($0)" } ?? "")
            """
        return try await database.reader.read { db in
            try LibraryGridItem.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Number of photos matching a smart album's rule query. GRDB performs the
    /// decode/read on its reader pool, so the surrounding Swift task can be
    /// cancelled/debounced without blocking the main actor.
    func count(matching query: SmartAlbumQuery) async throws -> Int {
        let (whereSQL, arguments) = Self.whereClause(for: query)
        let sql = "SELECT COUNT(*) FROM photo_metadata \(whereSQL)"
        return try await database.reader.read { db in
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

    /// Place names the library actually contains, most-photographed first — the
    /// display spelling, not the folded search text.
    ///
    /// Two jobs: autosuggest, and telling a search term apart from a camera name
    /// without guessing. "fukuoka" is a place because the library says so, so the
    /// parser never has to decide what a word looks like.
    func distinctPlaceTerms(limit: Int = 400) throws -> [String] {
        try database.reader.read { db in
            var seen = Set<String>()
            var terms: [String] = []
            // Locality first: it is what people type. Then the wider names, so a
            // country or prefecture still matches when no city was resolved.
            for column in ["placeLocality", "placeSubLocality", "placeAdminArea", "placeCountry"] {
                let rows = try String.fetchAll(
                    db,
                    sql: """
                        SELECT \(column) FROM photo_metadata
                        WHERE \(column) IS NOT NULL AND \(column) != ''
                        GROUP BY \(column) COLLATE NOCASE
                        ORDER BY COUNT(*) DESC
                        LIMIT ?
                        """,
                    arguments: [limit]
                )
                for row in rows where seen.insert(PlaceSearchText.normalized(row)).inserted {
                    terms.append(row)
                    if terms.count >= limit { return terms }
                }
            }
            return terms
        }
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

        // Free-typed contains-terms (smart albums): `LIKE %term%` across the
        // given columns, all terms ORed so any match includes the row.
        func addContains(_ terms: [String], columns: [String]) {
            let cleaned = terms
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { return }
            var ors: [String] = []
            for term in cleaned {
                for column in columns {
                    ors.append("\(column) LIKE ? COLLATE NOCASE")
                    values.append("%\(term)%")
                }
            }
            conditions.append("(" + ors.joined(separator: " OR ") + ")")
        }

        addSet(criteria.cameraBrands, column: "normalizedCameraManufacturer")
        addSet(criteria.cameraBodies, column: "normalizedCameraModel")
        addSet(criteria.lenses, column: "normalizedLensModel")
        addSet(Set(criteria.sensorFormats.map(\.rawValue)), column: "sensorFormat")

        addContains(criteria.cameraBrandTerms, columns: ["normalizedCameraManufacturer", "cameraManufacturer"])
        addContains(criteria.cameraBodyTerms, columns: ["normalizedCameraModel", "cameraModel"])
        addContains(criteria.lensTerms, columns: ["normalizedLensModel", "lensModel"])

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

    /// Compiles a smart album's rule query into a WHERE clause. Delegates to
    /// the shared `SmartAlbumSQLBuilder` (also used by `StatisticsQueries`).
    static func whereClause(for query: SmartAlbumQuery) -> (sql: String, arguments: StatementArguments) {
        SmartAlbumSQLBuilder.whereClause(for: query)
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
