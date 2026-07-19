import Foundation
import GRDB

/// Aggregate queries for the Statistics screen. All grouping and bucketing
/// happens in SQLite — Swift only shapes the results.
struct StatsDAO: Sendable {
    let database: AppDatabase

    private func scopeClause(_ scope: StatsDateScope) -> (sql: String, arguments: [DatabaseValueConvertible]) {
        guard let interval = scope.dateInterval() else { return ("", []) }
        return ("creationDate BETWEEN ? AND ?", [interval.lowerBound, interval.upperBound])
    }

    private func whereSQL(_ extra: String?, scope: StatsDateScope) -> (sql: String, arguments: StatementArguments) {
        let (scopeSQL, scopeArgs) = scopeClause(scope)
        var conditions: [String] = []
        if let extra { conditions.append(extra) }
        if !scopeSQL.isEmpty { conditions.append(scopeSQL) }
        let sql = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return (sql, StatementArguments(scopeArgs))
    }

    /// Oldest capture date in the index — the far end of the custom range picker.
    func earliestCreationDate() throws -> Date? {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT MIN(creationDate) FROM photo_metadata")
        }.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func totalPhotos(scope: StatsDateScope) throws -> Int {
        let (whereSQL, args) = whereSQL(nil, scope: scope)
        return try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata \(whereSQL)", arguments: args) ?? 0
        }
    }

    /// Usage counts grouped by an arbitrary column (camera, lens, sensor format).
    /// Percentages are shares of *all* photos in scope, so buckets always sum
    /// to ~100% regardless of missing metadata. With `includeUnknown` the rows
    /// whose column is NULL/empty are folded into one "Unknown" bucket —
    /// only valid without `limit` (a truncated list can't absorb the remainder).
    func usage(
        groupedBy column: String,
        scope: StatsDateScope,
        limit: Int? = nil,
        includeUnknown: Bool = false
    ) throws -> [UsageCount] {
        assert(limit == nil || !includeUnknown, "includeUnknown requires the full, un-limited list")
        let scopeTotal = try totalPhotos(scope: scope)
        let (whereSQL, args) = whereSQL("\(column) IS NOT NULL AND \(column) != ''", scope: scope)
        let limitSQL = limit.map { "LIMIT \($0)" } ?? ""
        let sql = """
            SELECT \(column) AS name, COUNT(*) AS count
            FROM photo_metadata
            \(whereSQL)
            GROUP BY \(column)
            ORDER BY count DESC
            \(limitSQL)
            """
        var results = try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: args).map { row in
                let count: Int = row["count"]
                return UsageCount(
                    name: row["name"],
                    count: count,
                    percentage: scopeTotal > 0 ? Double(count) / Double(scopeTotal) * 100 : 0
                )
            }
        }
        if includeUnknown {
            let unknownCount = scopeTotal - results.reduce(0) { $0 + $1.count }
            if unknownCount > 0 {
                results.append(UsageCount(
                    name: "Unknown",
                    count: unknownCount,
                    percentage: Double(unknownCount) / Double(scopeTotal) * 100,
                    isUnknown: true
                ))
                results.sort { $0.count > $1.count }
            }
        }
        return results
    }

    func cameraUsage(scope: StatsDateScope) throws -> [UsageCount] {
        try usage(groupedBy: "normalizedCameraModel", scope: scope, includeUnknown: true)
    }

    func lensUsage(scope: StatsDateScope) throws -> [UsageCount] {
        try usage(groupedBy: "normalizedLensModel", scope: scope, includeUnknown: true)
    }

    /// NULL/empty rows are merged with the `unknown` rawValue bucket so the
    /// chart shows a single Unknown slice.
    func sensorFormatUsage(scope: StatsDateScope) throws -> [UsageCount] {
        let rows = try usage(groupedBy: "sensorFormat", scope: scope, includeUnknown: true)
        var merged: [UsageCount] = []
        var unknown: UsageCount?
        for row in rows {
            if row.isUnknown || row.name == SensorFormat.unknown.rawValue {
                if var existing = unknown {
                    existing.count += row.count
                    existing.percentage += row.percentage
                    unknown = existing
                } else {
                    var first = row
                    first.name = SensorFormat.unknown.rawValue
                    first.isUnknown = true
                    unknown = first
                }
            } else {
                merged.append(row)
            }
        }
        if let unknown {
            merged.append(unknown)
            merged.sort { $0.count > $1.count }
        }
        return merged
    }

    /// Photos with no capture date — invisible to every non-all-time scope.
    func undatedCount() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata WHERE creationDate IS NULL") ?? 0
        }
    }

    /// Focal length histogram over the spec's zoom buckets.
    func focalLengthHistogram(equivalent: Bool, scope: StatsDateScope) throws -> [HistogramBucket] {
        let column = equivalent ? "equivalentFocalLength" : "focalLength"
        let (whereSQL, args) = whereSQL("\(column) IS NOT NULL", scope: scope)
        let sql = "SELECT \(column) AS value FROM photo_metadata \(whereSQL)"
        return try database.reader.read { db in
            let values = try Double.fetchAll(db, sql: sql, arguments: args)
            return FocalHistogramBucket.allCases.map { bucket in
                let (lower, upper) = bucket.range
                let count = values.lazy.filter { value in
                    value >= lower && (upper.map { value < $0 } ?? true)
                }.count
                return HistogramBucket(label: bucket.label, lowerBound: lower, upperBound: upper, count: count)
            }
        }
    }

    /// Headline summary for the cards at the top of the Statistics screen.
    func summary(scope: StatsDateScope) throws -> StatsSummary {
        let total = try totalPhotos(scope: scope)
        let topCamera = try usage(groupedBy: "normalizedCameraModel", scope: scope, limit: 1).first?.name
        let topLens = try usage(groupedBy: "normalizedLensModel", scope: scope, limit: 1).first?.name
        let topFormat = try usage(groupedBy: "sensorFormat", scope: scope, limit: 1)
            .first.flatMap { SensorFormat(rawValue: $0.name) }
        let topFocal = try mostFrequentValue(column: "focalLength", scope: scope)
        let topEquivalent = try mostFrequentValue(column: "equivalentFocalLength", scope: scope)
        return StatsSummary(
            totalPhotos: total,
            mostUsedCamera: topCamera,
            mostUsedLens: topLens,
            mostUsedFocalLength: topFocal,
            mostUsedEquivalentFocalLength: topEquivalent,
            mostUsedSensorFormat: topFormat
        )
    }

    /// Histogram over caller-provided ranges (ISO / aperture / shutter groups).
    func rangeHistogram(
        column: String,
        groups: [(label: String, range: NumericRangeFilter)],
        scope: StatsDateScope
    ) throws -> [HistogramBucket] {
        let (whereSQL, args) = whereSQL("\(column) IS NOT NULL", scope: scope)
        let sql = "SELECT \(column) AS value FROM photo_metadata \(whereSQL)"
        return try database.reader.read { db in
            let values = try Double.fetchAll(db, sql: sql, arguments: args)
            return groups.map { group in
                let count = values.lazy.filter { group.range.contains($0) }.count
                return HistogramBucket(
                    label: group.label,
                    lowerBound: group.range.lowerBound ?? 0,
                    upperBound: group.range.upperBound,
                    count: count
                )
            }
        }
    }

    /// Most common value, average, and median for a numeric column.
    func valueStats(column: String, scope: StatsDateScope) throws -> (mostCommon: Double?, average: Double?, median: Double?) {
        let (whereSQL, args) = whereSQL("\(column) IS NOT NULL", scope: scope)
        return try database.reader.read { db in
            let mostCommon = try Double.fetchOne(
                db,
                sql: """
                    SELECT \(column) FROM photo_metadata \(whereSQL)
                    GROUP BY \(column) ORDER BY COUNT(*) DESC LIMIT 1
                    """,
                arguments: args
            )
            let average = try Double.fetchOne(
                db,
                sql: "SELECT AVG(\(column)) FROM photo_metadata \(whereSQL)",
                arguments: args
            )
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(\(column)) FROM photo_metadata \(whereSQL)",
                arguments: args
            ) ?? 0
            var median: Double?
            if count > 0 {
                median = try Double.fetchOne(
                    db,
                    sql: """
                        SELECT \(column) FROM photo_metadata \(whereSQL)
                        ORDER BY \(column) LIMIT 1 OFFSET \(count / 2)
                        """,
                    arguments: args
                )
            }
            return (mostCommon, average, median)
        }
    }

    /// Photos per month for the top camera bodies — the usage trend chart.
    struct MonthlyCount: Equatable, Sendable, Identifiable {
        var month: String
        var name: String
        var count: Int
        var id: String { "\(month)|\(name)" }
    }

    func cameraMonthlyTrend(topBodies: Int, scope: StatsDateScope) throws -> [MonthlyCount] {
        let top = try usage(groupedBy: "normalizedCameraModel", scope: scope, limit: topBodies).map(\.name)
        guard !top.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: top.count).joined(separator: ", ")
        let (scopeSQL, scopeArgs) = scopeClause(scope)
        var conditions = [
            "normalizedCameraModel IN (\(placeholders))",
            "creationDate IS NOT NULL",
        ]
        if !scopeSQL.isEmpty { conditions.append(scopeSQL) }
        let sql = """
            SELECT strftime('%Y-%m', creationDate, 'unixepoch') AS month,
                   normalizedCameraModel AS name,
                   COUNT(*) AS count
            FROM photo_metadata
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month, name
            ORDER BY month
            """
        var combined: [DatabaseValueConvertible?] = top
        combined.append(contentsOf: scopeArgs)
        let arguments = StatementArguments(combined)
        return try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                MonthlyCount(month: row["month"], name: row["name"], count: row["count"])
            }
        }
    }

    /// Share of photos slower than the 1/equivalent-focal-length rule of thumb.
    func slowShutterShare(scope: StatsDateScope) throws -> Double? {
        let condition = "shutterSpeedSeconds IS NOT NULL AND equivalentFocalLength IS NOT NULL AND equivalentFocalLength > 0"
        let (whereSQL, args) = whereSQL(condition, scope: scope)
        return try database.reader.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM photo_metadata \(whereSQL)",
                arguments: args
            ) ?? 0
            guard total > 0 else { return nil }
            let slow = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM photo_metadata \(whereSQL) AND shutterSpeedSeconds > 1.0 / equivalentFocalLength",
                arguments: args
            ) ?? 0
            return Double(slow) / Double(total) * 100
        }
    }

    private func mostFrequentValue(column: String, scope: StatsDateScope) throws -> Double? {
        let (whereSQL, args) = whereSQL("\(column) IS NOT NULL", scope: scope)
        let sql = """
            SELECT \(column) AS value, COUNT(*) AS count
            FROM photo_metadata
            \(whereSQL)
            GROUP BY \(column)
            ORDER BY count DESC
            LIMIT 1
            """
        return try database.reader.read { db in
            try Double.fetchOne(db, sql: sql, arguments: args)
        }
    }
}
