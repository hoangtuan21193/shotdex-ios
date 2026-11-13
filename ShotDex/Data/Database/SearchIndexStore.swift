import Foundation
import GRDB

/// Builds the search index (FS-01.03c §1) from the library: every camera, lens,
/// place, date and capture fact the visible photos have, with a count and the
/// newest photo.
///
/// One read pass over `photo_metadata` aggregated in Swift, one SQL pass for
/// the kinds that only the smart album compiler knows how to test (Live Photo,
/// RAW…), one for keywords — then a single write that swaps the table and
/// rebuilds the FTS5 index. Everything is derived, so a rebuild is always
/// safe; it never touches a row the user typed.
struct SearchIndexStore: Sendable {
    let database: AppDatabase

    /// Rows a rebuild would write, for tests and for `rebuild()`.
    func computeGroups(calendar: Calendar = .current) throws -> [PendingGroup] {
        try database.reader.read { db in
            var groups = try Self.metadataGroups(db, calendar: calendar)
            groups += try Self.kindGroups(db)
            groups += try Self.keywordGroups(db)
            return groups
        }
    }

    /// Replaces the index with what the library holds now.
    func rebuild(calendar: Calendar = .current) throws {
        let groups = try computeGroups(calendar: calendar)
        let encoder = JSONEncoder()
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM search_group")
            let insert = try db.makeStatement(sql: """
                INSERT INTO search_group (category, name, folded, count, keyAssetId, rule)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            for group in groups {
                let rule = String(decoding: try encoder.encode(group.rule), as: UTF8.self)
                try insert.execute(arguments: [
                    group.category.rawValue, group.name, SearchFolding.fold(group.name),
                    group.count, group.keyAssetId, rule,
                ])
            }
            try db.execute(sql: "INSERT INTO search_group_fts(search_group_fts) VALUES('rebuild')")
        }
    }

    /// A group before it has a row id.
    struct PendingGroup: Equatable, Sendable {
        var category: SearchGroupCategory
        var name: String
        var count: Int
        var keyAssetId: String?
        var rule: SmartAlbumRule
    }

    // MARK: Metadata pass

    /// Running count + newest photo for one value.
    private struct Tally {
        var count = 0
        var newest: (date: Int, assetId: String)?
        var rule: SmartAlbumRule
        var name: String

        mutating func add(_ assetId: String, _ date: Int?) {
            count += 1
            let key = (date ?? 0, assetId)
            if newest == nil || key > newest! { newest = key }
        }
    }

    private static func metadataGroups(_ db: Database, calendar: Calendar) throws -> [PendingGroup] {
        let rows = try Row.fetchCursor(db, sql: """
            SELECT assetId, creationDate,
                   COALESCE(NULLIF(normalizedCameraModel, ''), cameraModel) AS camera,
                   COALESCE(NULLIF(normalizedCameraManufacturer, ''), cameraManufacturer) AS brand,
                   COALESCE(NULLIF(normalizedLensModel, ''), lensModel) AS lens,
                   sensorFormat, iso, focalLength, aperture, latitude,
                   placeLocality, placeSubLocality, placeAdminArea, placeCountry
            FROM photo_metadata
            WHERE \(PhotoVisibility.condition)
            """)
        var tallies: [String: Tally] = [:]
        func add(_ category: SearchGroupCategory, _ key: String, _ name: @autoclosure () -> String,
                 _ rule: @autoclosure () -> SmartAlbumRule, _ assetId: String, _ date: Int?) {
            let id = category.rawValue + "\u{1}" + key
            if tallies[id] == nil { tallies[id] = Tally(rule: rule(), name: name()) }
            tallies[id]!.add(assetId, date)
        }
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")

        while let row = try rows.next() {
            let assetId: String = row["assetId"]
            let date: Int? = row["creationDate"]
            if let camera: String = row["camera"], !camera.isEmpty {
                add(.camera, SearchFolding.fold(camera), camera,
                    SmartAlbumRule(field: .cameraBody, op: .isExactly, text: camera), assetId, date)
            }
            if let brand: String = row["brand"], !brand.isEmpty {
                add(.cameraBrand, SearchFolding.fold(brand), brand,
                    SmartAlbumRule(field: .cameraBrand, op: .isExactly, text: brand), assetId, date)
            }
            if let lens: String = row["lens"], !lens.isEmpty {
                add(.lens, SearchFolding.fold(lens), lens,
                    SmartAlbumRule(field: .lens, op: .isExactly, text: lens), assetId, date)
            }
            if let format: String = row["sensorFormat"], !format.isEmpty {
                add(.sensorFormat, format, SensorFormat(rawValue: format)?.displayName ?? format,
                    SmartAlbumRule(field: .sensorFormat, op: .isExactly, text: format), assetId, date)
            }
            if let iso: Int = row["iso"], iso > 0 {
                add(.iso, String(iso), "ISO \(iso)",
                    SmartAlbumRule(field: .iso, op: .equalTo, number: Double(iso)), assetId, date)
            }
            if let focal: Double = row["focalLength"], focal > 0 {
                let mm = Int(focal.rounded())
                add(.focalLength, String(mm), "\(mm)mm",
                    SmartAlbumRule(field: .focalLength, op: .inRange, number: Double(mm) - 0.5, numberUpper: Double(mm) + 0.4999),
                    assetId, date)
            }
            if let aperture: Double = row["aperture"], aperture > 0 {
                let value = (aperture * 10).rounded() / 10
                let text = NumericFieldKind.double.format(value)
                add(.aperture, text, "f/\(text)",
                    SmartAlbumRule(field: .aperture, op: .inRange, number: value - 0.05, numberUpper: value + 0.0499),
                    assetId, date)
            }
            // One group per name, however many address levels carry it
            // (`place contains` matches them all anyway), and a photo counts
            // once even when its city and prefecture share a name.
            var placesOfPhoto = Set<String>()
            for column in ["placeLocality", "placeSubLocality", "placeAdminArea", "placeCountry"] {
                guard let place: String = row[column], !place.isEmpty else { continue }
                let key = PlaceSearchText.normalized(place)
                guard !key.isEmpty, placesOfPhoto.insert(key).inserted else { continue }
                add(.place, key, place, SmartAlbumRule(field: .place, op: .contains, text: place), assetId, date)
            }
            if let date {
                let instant = Date(timeIntervalSince1970: TimeInterval(date))
                let parts = calendar.dateComponents([.year, .month, .weekday], from: instant)
                if let year = parts.year, let month = parts.month {
                    let yearInterval = calendar.dateInterval(of: .year, for: instant)
                    add(.year, String(year), String(year),
                        SmartAlbumRule(field: .dateTaken, op: .inRange,
                                       number: yearInterval?.start.timeIntervalSince1970,
                                       numberUpper: yearInterval.map { $0.end.timeIntervalSince1970 - 1 }),
                        assetId, date)
                    let captureMonth = CaptureMonth(year: year, month: month)
                    add(.month, String(format: "%04d-%02d", year, month),
                        monthFormatter.string(from: captureMonth.anchorDate(calendar: calendar)),
                        SmartAlbumRule(field: .dateTaken, op: .inMonth,
                                       number: captureMonth.anchorDate(calendar: calendar).timeIntervalSince1970),
                        assetId, date)
                    if let monthOfYear = CaptureMonthOfYear(rawValue: month) {
                        add(.monthOfYear, monthOfYear.value, monthOfYear.label,
                            SmartAlbumRule(field: .monthOfYear, op: .isExactly, text: monthOfYear.value), assetId, date)
                    }
                    let latitude: Double? = row["latitude"]
                    let seasonMonth = (latitude ?? 0) < 0 ? ((month + 5) % 12) + 1 : month
                    if let season = CaptureSeason.allCases.first(where: { $0.months.contains(seasonMonth) }) {
                        add(.season, season.rawValue, season.label,
                            SmartAlbumRule(field: .season, op: .isExactly, text: season.rawValue), assetId, date)
                    }
                }
                if let weekday = parts.weekday {
                    // Calendar: 1 = Sunday; SQLite %w: 0 = Sunday.
                    let day = weekday - 1
                    for value in CaptureWeekday.allCases where value.days.contains(day) {
                        add(.dayOfWeek, value.rawValue, value.label,
                            SmartAlbumRule(field: .dayOfWeek, op: .isExactly, text: value.rawValue), assetId, date)
                    }
                }
            }
        }
        return tallies.compactMap { id, tally in
            guard let category = SearchGroupCategory(rawValue: String(id.split(separator: "\u{1}").first ?? "")) else { return nil }
            return PendingGroup(category: category, name: tally.name, count: tally.count,
                                keyAssetId: tally.newest?.assetId, rule: tally.rule)
        }
    }

    // MARK: Kinds pass

    /// Photo kinds and file types, each tested by the smart album compiler —
    /// one scan with a SUM per value.
    private static func kindGroups(_ db: Database) throws -> [PendingGroup] {
        var candidates: [(SearchGroupCategory, String, SmartAlbumRule)] = []
        for kind in PhotoKind.allCases {
            candidates.append((.photoKind, kind.label, SmartAlbumRule(field: .photoKind, op: .isExactly, text: kind.rawValue)))
        }
        for type in PhotoFileType.allCases {
            candidates.append((.fileType, type.displayName, SmartAlbumRule(field: .fileType, op: .isExactly, text: type.rawValue)))
        }
        var columns: [String] = []
        var values: [DatabaseValueConvertible] = []
        var kept: [(SearchGroupCategory, String, SmartAlbumRule)] = []
        for candidate in candidates {
            guard let clause = SmartAlbumSQLBuilder.clause(for: candidate.2) else { continue }
            columns.append("SUM(CASE WHEN \(clause.sql) THEN 1 ELSE 0 END)")
            values.append(contentsOf: clause.values)
            columns.append("MAX(CASE WHEN \(clause.sql) THEN printf('%012d|%s', COALESCE(creationDate, 0), assetId) END)")
            values.append(contentsOf: clause.values)
            kept.append(candidate)
        }
        guard !kept.isEmpty, let row = try Row.fetchOne(
            db,
            sql: "SELECT \(columns.joined(separator: ", ")) FROM photo_metadata WHERE \(PhotoVisibility.condition)",
            arguments: StatementArguments(values)
        ) else { return [] }
        return kept.enumerated().compactMap { index, candidate in
            let count: Int = row[index * 2] ?? 0
            guard count > 0 else { return nil }
            let newest: String? = row[index * 2 + 1]
            return PendingGroup(category: candidate.0, name: candidate.1, count: count,
                                keyAssetId: newest.flatMap(Self.assetId(fromNewestKey:)), rule: candidate.2)
        }
    }

    // MARK: Keywords

    private static func keywordGroups(_ db: Database) throws -> [PendingGroup] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT MIN(k.keyword) AS name, COUNT(DISTINCT k.assetId) AS count,
                   MAX(printf('%012d|%s', COALESCE(photo_metadata.creationDate, 0), photo_metadata.assetId)) AS newest
            FROM (\(PhotoKeywordStore.everyKeywordSQL)) AS k
            JOIN photo_metadata ON photo_metadata.assetId = k.assetId
            WHERE \(PhotoVisibility.condition)
            GROUP BY k.foldKey
            """)
        return rows.compactMap { row in
            guard let name: String = row["name"], !name.isEmpty else { return nil }
            let newest: String? = row["newest"]
            return PendingGroup(category: .keyword, name: name, count: row["count"],
                                keyAssetId: newest.flatMap(Self.assetId(fromNewestKey:)),
                                rule: SmartAlbumRule(field: .keyword, op: .hasKeyword, text: name))
        }
    }

    /// `000001700000000|ASSET-ID` → `ASSET-ID`.
    private static func assetId(fromNewestKey key: String) -> String? {
        guard let bar = key.firstIndex(of: "|") else { return nil }
        return String(key[key.index(after: bar)...])
    }
}
