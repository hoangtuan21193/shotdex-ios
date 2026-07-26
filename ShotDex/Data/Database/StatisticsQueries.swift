import Foundation
import GRDB

/// Aggregate queries for the Statistics screen. All grouping and bucketing
/// happens in SQLite — Swift only shapes the results.
struct StatisticsQueries: Sendable {
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

// MARK: - Dashboard chart aggregation

extension StatisticsQueries {
    /// Runs a dashboard chart spec's query and returns its plotted points.
    /// Dispatches on `kind`; all column names come from closed enums on
    /// `ChartDimension` / `MetricField` (never user text), and only bound
    /// values originate from user input, so the string-built SQL is injection
    /// free. The date `scope` ANDs on top of the spec's own `filter`.
    func chartData(for spec: ChartSpec, scope: StatsDateScope) throws -> [ChartDatum] {
        switch spec.kind {
        case .kpi:
            if let dimension = spec.dimension {
                // Top group by count — "Most used X". Binned/temporal data isn't
                // value-sorted, so pick the max rather than the first row.
                let grouped = try groupedData(
                    dimension: dimension,
                    metric: .photoCount,
                    filter: spec.filter,
                    scope: scope,
                    topN: 0,
                    includeUnknown: false
                )
                guard let top = grouped.filter({ !$0.isUnknown }).max(by: { $0.value < $1.value }) else {
                    return []
                }
                return [top]
            }
            guard let value = try scalar(metric: spec.metric, filter: spec.filter, scope: scope) else {
                return []
            }
            return [ChartDatum(label: spec.metric.displayName, value: value)]

        case .line:
            return try temporalData(
                dimension: spec.dimension ?? .dateMonth,
                metric: spec.metric,
                seriesSplit: spec.seriesSplit,
                filter: spec.filter,
                scope: scope,
                topSeries: spec.topN
            )

        case .bar, .donut:
            guard let dimension = spec.dimension else { return [] }
            return try groupedData(
                dimension: dimension,
                metric: spec.metric,
                filter: spec.filter,
                scope: scope,
                topN: spec.topN,
                includeUnknown: spec.metric.aggregation == .count
            )
        }
    }

    // MARK: Dispatch by axis kind

    private func groupedData(
        dimension: ChartDimension,
        metric: ChartMetric,
        filter: SmartAlbumQuery,
        scope: StatsDateScope,
        topN: Int,
        includeUnknown: Bool
    ) throws -> [ChartDatum] {
        switch dimension.axisKind {
        case .categorical:
            return try categoricalData(
                dimension: dimension, metric: metric, filter: filter,
                scope: scope, topN: topN, includeUnknown: includeUnknown
            )
        case .binned:
            return try binnedData(dimension: dimension, metric: metric, filter: filter, scope: scope)
        case .temporal:
            return try temporalData(
                dimension: dimension, metric: metric, seriesSplit: nil,
                filter: filter, scope: scope, topSeries: 0
            )
        }
    }

    // MARK: Filter + scope helpers

    /// The spec filter and date scope as ANDable conditions + bound values
    /// (no `WHERE`, no leading keyword). Column names inside come only from the
    /// closed-enum rule builder; values are parameters.
    private func filterAndScope(
        _ filter: SmartAlbumQuery,
        _ scope: StatsDateScope
    ) -> (conditions: [String], values: [DatabaseValueConvertible]) {
        var conditions: [String] = []
        var values: [DatabaseValueConvertible] = []
        let (filterSQL, filterValues) = SmartAlbumSQLBuilder.predicate(for: filter)
        if !filterSQL.isEmpty {
            conditions.append(filterSQL)
            values.append(contentsOf: filterValues)
        }
        let (scopeSQL, scopeArgs) = scopeClause(scope)
        if !scopeSQL.isEmpty {
            conditions.append(scopeSQL)
            values.append(contentsOf: scopeArgs)
        }
        return (conditions, values)
    }

    private static func whereSQL(_ conditions: [String]) -> String {
        conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
    }

    /// Reads a group key as a String regardless of column affinity — text
    /// dimensions arrive as strings, `favorite` as an integer 0/1.
    private static func stringKey(_ value: DatabaseValue) -> String {
        if let string = String.fromDatabaseValue(value) { return string }
        if let int = Int64.fromDatabaseValue(value) { return String(int) }
        if let double = Double.fromDatabaseValue(value) { return String(double) }
        return ""
    }

    private func countRows(conditions: [String], values: [DatabaseValueConvertible]) throws -> Int {
        let sql = "SELECT COUNT(*) FROM photo_metadata \(Self.whereSQL(conditions))"
        return try database.reader.read { db in
            try Int.fetchOne(db, sql: sql, arguments: StatementArguments(values)) ?? 0
        }
    }

    /// SQL aggregate expression for a metric, plus a NOT-NULL guard (nil for
    /// plain counting). `.median` never reaches here for grouped charts.
    private func metricExpression(_ metric: ChartMetric) -> (expr: String, notNull: String?) {
        guard let field = metric.field, metric.aggregation != .count else {
            return ("COUNT(*)", nil)
        }
        return (metric.aggregation.sql(columnExpression: field.columnExpression), field.notNullClause)
    }

    // MARK: Categorical

    private func categoricalData(
        dimension: ChartDimension,
        metric: ChartMetric,
        filter: SmartAlbumQuery,
        scope: StatsDateScope,
        topN: Int,
        includeUnknown: Bool
    ) throws -> [ChartDatum] {
        let column = dimension.groupColumn
        let isCount = metric.field == nil || metric.aggregation == .count
        let (aggExpr, aggNotNull) = metricExpression(metric)

        var (conditions, values) = filterAndScope(filter, scope)
        // `favorite` is an integer flag (never NULL / empty); text categoricals
        // exclude NULL/blank so they don't form a spurious "" bucket.
        if dimension != .favorite {
            conditions.insert("\(column) IS NOT NULL AND \(column) != ''", at: 0)
        }
        if let aggNotNull { conditions.append(aggNotNull) }

        let limitSQL = topN > 0 ? "LIMIT \(topN)" : ""
        let sql = """
            SELECT \(column) AS key, \(aggExpr) AS value
            FROM photo_metadata
            \(Self.whereSQL(conditions))
            GROUP BY \(column)
            ORDER BY value DESC
            \(limitSQL)
            """
        var data = try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values)).map { row -> ChartDatum in
                let key = Self.stringKey(row["key"])
                let value: Double = row["value"] ?? 0
                return ChartDatum(
                    label: dimension.label(forKey: key),
                    value: value,
                    drillKey: key
                )
            }
        }

        // Synthetic "Unknown" bucket — counted directly from NULL/blank rows so
        // it's correct even when `topN` truncates the known buckets. Only for
        // counts of a text dimension.
        if includeUnknown, isCount, dimension != .favorite {
            var (unknownConditions, unknownValues) = filterAndScope(filter, scope)
            unknownConditions.insert("(\(column) IS NULL OR \(column) = '')", at: 0)
            let unknown = try countRows(conditions: unknownConditions, values: unknownValues)
            if unknown > 0 {
                data.append(ChartDatum(
                    label: "Unknown", value: Double(unknown), drillKey: nil, isUnknown: true
                ))
            }
        }
        return data
    }

    // MARK: Binned numeric

    /// Bins numeric rows in Swift (same approach as `rangeHistogram`) so a
    /// single fetch serves both counts and per-bucket aggregates.
    private func binnedData(
        dimension: ChartDimension,
        metric: ChartMetric,
        filter: SmartAlbumQuery,
        scope: StatsDateScope
    ) throws -> [ChartDatum] {
        guard let bins = dimension.bins else { return [] }
        let column = dimension.groupColumn
        let isCount = metric.field == nil || metric.aggregation == .count

        var (conditions, values) = filterAndScope(filter, scope)
        conditions.insert("\(column) IS NOT NULL", at: 0)
        let metricField = isCount ? nil : metric.field
        if let metricField { conditions.append(metricField.notNullClause) }

        let metricSelect = metricField.map { ", \($0.columnExpression) AS m" } ?? ""
        let sql = """
            SELECT \(column) AS dim\(metricSelect)
            FROM photo_metadata
            \(Self.whereSQL(conditions))
            """
        let pairs: [(dim: Double, m: Double?)] = try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values)).map { row in
                (dim: row["dim"] ?? 0, m: metricField != nil ? row["m"] : nil)
            }
        }

        return bins.map { bin in
            let inBin = pairs.filter { bin.range.contains($0.dim) }
            let value: Double
            if isCount {
                value = Double(inBin.count)
            } else {
                let ms = inBin.compactMap(\.m)
                value = Self.reduce(ms, using: metric.aggregation)
            }
            return ChartDatum(label: bin.label, value: value, drillKey: bin.label)
        }
    }

    private static func reduce(_ values: [Double], using aggregation: MetricAggregation) -> Double {
        guard !values.isEmpty else { return 0 }
        switch aggregation {
        case .count: return Double(values.count)
        case .sum: return values.reduce(0, +)
        case .average: return values.reduce(0, +) / Double(values.count)
        case .min: return values.min() ?? 0
        case .max: return values.max() ?? 0
        case .median:
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }

    // MARK: Temporal (line)

    private func temporalData(
        dimension: ChartDimension,
        metric: ChartMetric,
        seriesSplit: ChartDimension?,
        filter: SmartAlbumQuery,
        scope: StatsDateScope,
        topSeries: Int
    ) throws -> [ChartDatum] {
        let fmt = dimension.strftimeFormat ?? "%Y-%m"
        let (aggExpr, aggNotNull) = metricExpression(metric)

        var conditions = ["creationDate IS NOT NULL"]
        var values: [DatabaseValueConvertible] = []
        if let aggNotNull { conditions.append(aggNotNull) }

        // Optional split into one series per top-N value of a categorical dim.
        var seriesColumn: String?
        if let split = seriesSplit, split.axisKind == .categorical {
            let keys = try topCategoryKeys(
                column: split.groupColumn, filter: filter, scope: scope,
                limit: max(1, topSeries)
            )
            guard !keys.isEmpty else { return [] }
            seriesColumn = split.groupColumn
            let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
            conditions.append("\(split.groupColumn) IN (\(placeholders))")
            values.append(contentsOf: keys)
        }

        let (fsConditions, fsValues) = filterAndScope(filter, scope)
        conditions.append(contentsOf: fsConditions)
        values.append(contentsOf: fsValues)

        let seriesSelect = seriesColumn.map { ", \($0) AS series" } ?? ""
        let seriesGroup = seriesColumn.map { ", \($0)" } ?? ""
        let sql = """
            SELECT strftime('\(fmt)', creationDate, 'unixepoch') AS period\(seriesSelect),
                   \(aggExpr) AS value
            FROM photo_metadata
            \(Self.whereSQL(conditions))
            GROUP BY period\(seriesGroup)
            ORDER BY period
            """
        return try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values)).map { row in
                ChartDatum(
                    label: row["period"],
                    value: row["value"] ?? 0,
                    drillKey: nil,
                    series: seriesColumn != nil ? Self.stringKey(row["series"]) : nil
                )
            }
        }
    }

    /// Top-N distinct values of a categorical column by photo count, within the
    /// filter + scope — the series shown on a split line chart.
    private func topCategoryKeys(
        column: String,
        filter: SmartAlbumQuery,
        scope: StatsDateScope,
        limit: Int
    ) throws -> [String] {
        var (conditions, values) = filterAndScope(filter, scope)
        conditions.insert("\(column) IS NOT NULL AND \(column) != ''", at: 0)
        let sql = """
            SELECT \(column) AS key, COUNT(*) AS c
            FROM photo_metadata
            \(Self.whereSQL(conditions))
            GROUP BY \(column)
            ORDER BY c DESC
            LIMIT \(limit)
            """
        return try database.reader.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values)).map { Self.stringKey($0["key"]) }
        }
    }

    // MARK: Scalar (KPI without a dimension)

    private func scalar(
        metric: ChartMetric,
        filter: SmartAlbumQuery,
        scope: StatsDateScope
    ) throws -> Double? {
        var (conditions, values) = filterAndScope(filter, scope)

        // Count of rows — no field needed.
        if metric.field == nil || metric.aggregation == .count {
            return Double(try countRows(conditions: conditions, values: values))
        }
        guard let field = metric.field else { return nil }
        conditions.append(field.notNullClause)
        let args: StatementArguments = StatementArguments(values)

        if metric.aggregation == .median {
            let count = try countRows(conditions: conditions, values: values)
            guard count > 0 else { return nil }
            let sql = """
                SELECT \(field.columnExpression) FROM photo_metadata
                \(Self.whereSQL(conditions))
                ORDER BY \(field.columnExpression) LIMIT 1 OFFSET \(count / 2)
                """
            return try database.reader.read { db in
                try Double.fetchOne(db, sql: sql, arguments: args)
            }
        }

        let expr = metric.aggregation.sql(columnExpression: field.columnExpression)
        let sql = "SELECT \(expr) FROM photo_metadata \(Self.whereSQL(conditions))"
        return try database.reader.read { db in
            try Double.fetchOne(db, sql: sql, arguments: args)
        }
    }
}
