import Foundation

/// A user-configured chart on the Statistics dashboard. Persisted as JSON in
/// the `stat_charts.config` column (see `StatChart` / `ChartStore`). Every
/// spec is: a chart *kind*, an X-axis *dimension* (group-by), a Y-axis
/// *metric* (aggregation), and an optional *filter* (the same rule query as
/// smart albums) restricting which photos count. The dashboard's date scope
/// applies on top of `filter`.
struct ChartSpec: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var kind: ChartKind
    /// Group-by / X-axis. `nil` only for a `.kpi` scalar (metric over the
    /// whole set); every other kind requires a dimension.
    var dimension: ChartDimension?
    /// Y-axis aggregation. Defaults to counting photos.
    var metric: ChartMetric
    /// Extra condition; `.empty` means the whole (scoped) library.
    var filter: SmartAlbumQuery
    /// `.line` only: split into one line per value of this categorical
    /// dimension (e.g. per camera body). `nil` renders a single line.
    var seriesSplit: ChartDimension?
    /// Max categorical/binned buckets to show (bar/donut). Ignored elsewhere.
    var topN: Int
    /// This chart's own date range. Each spec scopes independently — there
    /// is no global dashboard scope.
    var scope: StatsDateScope

    init(
        id: String = UUID().uuidString,
        title: String,
        kind: ChartKind,
        dimension: ChartDimension?,
        metric: ChartMetric = .photoCount,
        filter: SmartAlbumQuery = .empty,
        seriesSplit: ChartDimension? = nil,
        topN: Int = 8,
        scope: StatsDateScope = .allTime
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dimension = dimension
        self.metric = metric
        self.filter = filter
        self.seriesSplit = seriesSplit
        self.topN = topN
        self.scope = scope
    }

    // MARK: Codable (tolerant — survive future field additions)

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, dimension, metric, filter, seriesSplit, topN, scope
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Chart"
        kind = try c.decodeIfPresent(ChartKind.self, forKey: .kind) ?? .bar
        dimension = try c.decodeIfPresent(ChartDimension.self, forKey: .dimension)
        metric = try c.decodeIfPresent(ChartMetric.self, forKey: .metric) ?? .photoCount
        filter = try c.decodeIfPresent(SmartAlbumQuery.self, forKey: .filter) ?? .empty
        seriesSplit = try c.decodeIfPresent(ChartDimension.self, forKey: .seriesSplit)
        topN = try c.decodeIfPresent(Int.self, forKey: .topN) ?? 8
        scope = try c.decodeIfPresent(StatsDateScope.self, forKey: .scope) ?? .allTime
    }

    /// The dashboard a fresh install opens on (FS-07.01 §3), in order: the
    /// questions a photographer asks first — which camera, how many, which
    /// focal length, which body + lens pair, how much is shot slow, and when.
    /// None is fixed; every one edits and deletes like a chart the user built.
    static func defaultSpecs() -> [ChartSpec] {
        [
            ChartSpec(title: "Top Camera", kind: .bar, dimension: .cameraBody, topN: 5),
            ChartSpec(title: "Total Photos & Videos", kind: .kpi, dimension: nil, metric: .photoCount),
            ChartSpec(title: "Equivalent Focal Length", kind: .bar, dimension: .focalEquivalent),
            ChartSpec(title: "Body + Lens", kind: .bar, dimension: .cameraLensPair, topN: 5),
            ChartSpec(title: "Slow Shutter", kind: .kpi, dimension: nil, metric: .slowShutterShare),
            ChartSpec(
                title: "Photos per Month", kind: .line, dimension: .dateMonth,
                seriesSplit: .cameraBody, topN: 3
            ),
        ]
    }

    /// How many of `defaultSpecs()` the first seed generation planted (Top
    /// Camera, Total Photos & Videos). An install seeded then gets the rest
    /// appended once — see `ChartStore.loadCharts(seededVersion:)`.
    static let firstSeedGenerationCount = 2

    /// Whether the card offers its Donut · Bars switch (DUO_LOOP 13b): a
    /// share of a categorical dimension, counted — the one data shape both
    /// kinds draw. A bar of averages or of binned ISO has no donut.
    var switchesBetweenDonutAndBars: Bool {
        guard kind == .bar || kind == .donut, let dimension else { return false }
        return ChartKind.donut.allowedDimensions.contains(dimension)
            && ChartKind.donut.allowedAggregations.contains(metric.aggregation)
    }

    /// This chart drawn as `kind`, everything else kept; nil when the card
    /// has no switch or `kind` is not one of its two.
    func switched(to kind: ChartKind) -> ChartSpec? {
        guard switchesBetweenDonutAndBars, kind == .bar || kind == .donut else { return nil }
        var copy = self
        copy.kind = kind
        return copy
    }
}

// MARK: - Chart kind

/// The visual form of a chart, and the dimension/metric combinations it
/// accepts. The editor offers only `allowedDimensions` / `allowedAggregations`
/// for the current kind (mirrors `RuleFieldKind.allowedOperators`).
enum ChartKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bar     // horizontal bars: categorical or binned X, metric Y
    case donut   // share of a categorical dimension (count only)
    case line    // metric over time, optional per-series split
    case kpi     // a single number (scalar metric, or top group by count)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bar: "Bar"
        case .donut: "Donut"
        case .line: "Line (over time)"
        case .kpi: "Single value"
        }
    }

    var systemImage: String {
        switch self {
        case .bar: "chart.bar.fill"
        case .donut: "chart.pie.fill"
        case .line: "chart.line.uptrend.xyaxis"
        case .kpi: "number"
        }
    }

    /// Whether a dimension (group-by / X-axis) is required. Only `.kpi` allows
    /// no dimension (a scalar over the whole set).
    var requiresDimension: Bool { self != .kpi }

    /// Dimensions offered in the editor for this kind.
    var allowedDimensions: [ChartDimension] {
        switch self {
        case .bar:
            ChartDimension.allCases.filter { $0.axisKind == .categorical || $0.axisKind == .binned || $0.axisKind == .cyclic }
        case .donut:
            ChartDimension.allCases.filter { $0.axisKind == .categorical }
        case .line:
            ChartDimension.allCases.filter { $0.axisKind == .temporal }
        case .kpi:
            ChartDimension.allCases
        }
    }

    /// Aggregations offered in the editor for this kind. Median is only valid
    /// for a `.kpi` scalar — per-group median has no cheap SQL form.
    var allowedAggregations: [MetricAggregation] {
        switch self {
        case .bar, .line: [.count, .average, .sum, .min, .max, .slowShutterShare]
        case .donut: [.count]
        case .kpi: [.count, .average, .median, .sum, .min, .max, .slowShutterShare]
        }
    }
}

// MARK: - Dimension (X-axis / group-by)

/// How a dimension buckets rows: a distinct-value grouping, a set of numeric
/// bins, or a date truncation.
enum ChartAxisKind: Sendable {
    case categorical
    case binned
    case temporal
    /// Hour of the day or day of the week: a fixed set of buckets, every one
    /// drawn even when empty, in clock order.
    case cyclic
}

/// A photo attribute the X-axis groups by. Each case maps to a **hardcoded**
/// SQL column/expression (`groupColumn`) — the value is never taken from user
/// text, so it is safe to interpolate into SQL (StatisticsQueries builds SQL by string).
enum ChartDimension: String, Codable, CaseIterable, Identifiable, Sendable {
    // Categorical
    case cameraBody
    case cameraBrand
    case lens
    case sensorFormat
    case favorite
    /// Camera body and lens together — one bucket per (body, lens) pair, so
    /// each module of a phone is its own pair (FS-07.02 §5).
    case cameraLensPair
    // Binned numeric
    case iso
    case aperture
    case shutter
    case focalActual
    case focalEquivalent
    // Temporal
    case dateDay
    case dateMonth
    case dateYear
    // Cyclic — every photo folded onto one day or one week (FS-07.01 §2)
    case hourOfDay
    case weekday

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraBody: "Camera Model"
        case .cameraBrand: "Camera Brand"
        case .lens: "Lens"
        case .sensorFormat: "Sensor Format"
        case .favorite: "Favorite"
        case .cameraLensPair: "Camera + Lens"
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutter: "Shutter Speed"
        case .focalActual: "Focal Length"
        case .focalEquivalent: "Focal Length (FF equiv.)"
        case .dateDay: "Date (by day)"
        case .dateMonth: "Date (by month)"
        case .dateYear: "Date (by year)"
        case .hourOfDay: "Time of Day"
        case .weekday: "Weekday"
        }
    }

    var axisKind: ChartAxisKind {
        switch self {
        case .cameraBody, .cameraBrand, .lens, .sensorFormat, .favorite, .cameraLensPair: .categorical
        case .iso, .aperture, .shutter, .focalActual, .focalEquivalent: .binned
        case .dateDay, .dateMonth, .dateYear: .temporal
        case .hourOfDay, .weekday: .cyclic
        }
    }

    /// Hardcoded grouping column/expression — closed switch, NEVER raw string.
    var groupColumn: String {
        switch self {
        case .cameraBody: "normalizedCameraModel"
        case .cameraBrand: "normalizedCameraManufacturer"
        case .lens: "normalizedLensModel"
        case .sensorFormat: "sensorFormat"
        case .favorite: "isFavorite"
        case .cameraLensPair: "normalizedCameraModel"
        case .iso: "iso"
        case .aperture: "aperture"
        case .shutter: "shutterSpeedSeconds"
        case .focalActual: "focalLength"
        case .focalEquivalent: "equivalentFocalLength"
        case .dateDay, .dateMonth, .dateYear, .hourOfDay, .weekday: "creationDate"
        }
    }

    /// The second grouping column of a two-column dimension (the lens of a
    /// body + lens pair); `nil` for every one-column dimension. Closed switch,
    /// like `groupColumn`.
    var secondGroupColumn: String? {
        switch self {
        case .cameraLensPair: "normalizedLensModel"
        default: nil
        }
    }

    /// Whether the dimension can split a line chart into series — one
    /// categorical column only; a pair has no single series key.
    var splitsSeries: Bool { axisKind == .categorical && secondGroupColumn == nil }

    /// The drill key of a body + lens pair: a JSON array of the two names,
    /// because a lens name can hold any character a separator could use.
    static func pairKey(body: String, lens: String) -> String {
        let data = (try? JSONEncoder().encode([body, lens])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The two names inside a `pairKey`, or `nil` if the key is not one.
    static func pairNames(fromKey key: String) -> (body: String, lens: String)? {
        guard let names = try? JSONDecoder().decode([String].self, from: Data(key.utf8)),
              names.count == 2 else { return nil }
        return (names[0], names[1])
    }

    /// Buckets for a `.binned` dimension (nil otherwise). Reuses the Library
    /// filter quick-group ranges so binning is identical across the app.
    var bins: [(label: String, range: NumericRangeFilter)]? {
        switch self {
        case .iso:
            ISOQuickGroup.allCases.map { ($0.rawValue, $0.range) }
        case .aperture:
            ApertureQuickGroup.allCases.map { ($0.rawValue, $0.range) }
        case .shutter:
            ShutterQuickGroup.allCases.map { ($0.rawValue, $0.range) }
        case .focalActual, .focalEquivalent:
            FocalHistogramBucket.allCases.map { bucket in
                let (lower, upper) = bucket.range
                // Upper is exclusive in the focal buckets; nudge below it so
                // the inclusive NumericRangeFilter keeps the same boundaries.
                return (bucket.label, NumericRangeFilter(
                    lowerBound: lower,
                    upperBound: upper.map { $0 - 0.0001 }
                ))
            }
        default:
            nil
        }
    }

    /// Every bucket key of a `.cyclic` dimension, in the order drawn: 00…23,
    /// and Monday…Sunday as SQLite's `%w` numbers them (0 = Sunday).
    var cyclicKeys: [String]? {
        switch self {
        case .hourOfDay: (0..<24).map { String(format: "%02d", $0) }
        case .weekday: ["1", "2", "3", "4", "5", "6", "0"]
        default: nil
        }
    }

    /// Short weekday names indexed like `%w` (0 = Sunday).
    static var weekdaySymbols: [String] { Calendar.current.shortWeekdaySymbols }

    /// `strftime` format for a `.temporal` or `.cyclic` dimension (nil otherwise).
    var strftimeFormat: String? {
        switch self {
        case .dateDay: "%Y-%m-%d"
        case .dateMonth: "%Y-%m"
        case .dateYear: "%Y"
        case .hourOfDay: "%H"
        case .weekday: "%w"
        default: nil
        }
    }

    /// Display label for a raw group key (favorite 1/0 → words; others as-is).
    func label(forKey key: String) -> String {
        switch self {
        case .favorite: key == "1" ? "Favorite" : "Not favorite"
        case .cameraLensPair:
            Self.pairNames(fromKey: key).map { "\($0.body) · \($0.lens)" } ?? key
        case .hourOfDay:
            Int(key).map(String.init) ?? key
        case .weekday:
            Int(key).flatMap { Self.weekdaySymbols.indices.contains($0) ? Self.weekdaySymbols[$0] : nil } ?? key
        default: key
        }
    }

    /// A Library `FilterCriteria` that isolates the tapped bucket, for
    /// drill-down. `nil` when the dimension can't be expressed as a filter
    /// ("Not favorite"), and for temporal buckets: the filter has a month
    /// condition now, but tapping a point on a line is not specified
    /// (FS-07.01 §4).
    func drillCriteria(key: String) -> FilterCriteria? {
        var criteria = FilterCriteria()
        switch self {
        case .cameraBody:
            criteria.cameraBodies = [key]
        case .cameraBrand:
            criteria.cameraBrands = [key]
        case .lens:
            criteria.lenses = [key]
        case .sensorFormat:
            guard let format = SensorFormat(rawValue: key) else { return nil }
            criteria.sensorFormats = [format]
        case .favorite:
            guard key == "1" else { return nil }   // can't filter "not favorite"
            criteria.favoritesOnly = true
        case .cameraLensPair:
            guard let names = Self.pairNames(fromKey: key) else { return nil }
            criteria.cameraBodies = [names.body]
            criteria.lenses = [names.lens]
        case .iso, .aperture, .shutter, .focalActual, .focalEquivalent:
            guard let range = bins?.first(where: { $0.label == key })?.range else { return nil }
            switch self {
            case .iso: criteria.isoRange = range
            case .aperture: criteria.apertureRange = range
            case .shutter: criteria.shutterRange = range
            case .focalActual:
                criteria.focalRange = range
                criteria.focalLengthMode = .actual
            case .focalEquivalent:
                criteria.focalRange = range
                criteria.focalLengthMode = .equivalent
            default: break
            }
        case .dateDay, .dateMonth, .dateYear:
            return nil
        case .hourOfDay, .weekday:
            // The Library has no clock-hour or weekday filter yet (AC-57).
            return nil
        }
        return criteria
    }
}

// MARK: - Metric (Y-axis)

/// The statistic plotted on the Y-axis / shown by a KPI.
enum MetricAggregation: String, Codable, CaseIterable, Identifiable, Sendable {
    case count
    case average
    case median
    case sum
    case min
    case max
    /// Percentage of photos shot slower than 1 / equivalent focal length —
    /// the same rule as the Insights sentence. Takes no field.
    case slowShutterShare

    var id: String { rawValue }

    /// Whether the aggregation runs over a chosen field ("Of" in the editor).
    /// Counting and the slow-shutter share read fixed columns of their own.
    var needsField: Bool { self != .count && self != .slowShutterShare }

    var displayName: String {
        switch self {
        case .count: "Count"
        case .average: "Average"
        case .median: "Median"
        case .sum: "Total"
        case .min: "Minimum"
        case .max: "Maximum"
        case .slowShutterShare: "Slower than 1/focal length"
        }
    }

    /// SQL aggregate over a (hardcoded) column expression. `.count` ignores it.
    /// `.median` has no SQL aggregate form — handled separately for KPIs.
    func sql(columnExpression: String) -> String {
        switch self {
        case .count: "COUNT(*)"
        case .average: "AVG(\(columnExpression))"
        case .sum: "SUM(\(columnExpression))"
        case .min: "MIN(\(columnExpression))"
        case .max: "MAX(\(columnExpression))"
        case .median: "AVG(\(columnExpression))"   // never used for groups
        case .slowShutterShare: Self.slowShutterShareSQL
        }
    }

    /// Share (0…100) of rows exposed longer than 1 / equivalent focal length.
    /// Pair it with `slowShutterGuard` so rows missing either input stay out
    /// of the denominator.
    static let slowShutterShareSQL =
        "100.0 * AVG(CASE WHEN shutterSpeedSeconds > 1.0 / equivalentFocalLength THEN 1.0 ELSE 0.0 END)"
    static let slowShutterGuard =
        "shutterSpeedSeconds IS NOT NULL AND equivalentFocalLength IS NOT NULL AND equivalentFocalLength > 0"
}

/// A numeric photo attribute an aggregation can run over. Maps to a
/// **hardcoded** SQL expression — never raw user text.
enum MetricField: String, Codable, CaseIterable, Identifiable, Sendable {
    case iso
    case aperture
    case shutter
    case focalLength
    case equivalentFocalLength
    case fileSize
    case megapixels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .shutter: "Shutter Speed"
        case .focalLength: "Focal Length"
        case .equivalentFocalLength: "Focal Length (FF equiv.)"
        case .fileSize: "File Size"
        case .megapixels: "Megapixels"
        }
    }

    /// Hardcoded column/expression — closed switch, NEVER raw string.
    var columnExpression: String {
        switch self {
        case .iso: "iso"
        case .aperture: "aperture"
        case .shutter: "shutterSpeedSeconds"
        case .focalLength: "focalLength"
        case .equivalentFocalLength: "equivalentFocalLength"
        case .fileSize: "fileSize"
        case .megapixels: "(width * 1.0 * height) / 1000000.0"
        }
    }

    /// NOT-NULL guard so rows missing the input don't skew AVG/SUM.
    var notNullClause: String {
        switch self {
        case .megapixels: "width IS NOT NULL AND height IS NOT NULL"
        default: "\(columnExpression) IS NOT NULL"
        }
    }
}

/// A Y-axis metric: an aggregation, plus the field it runs over (`nil` only
/// for `.count`, which counts rows).
struct ChartMetric: Codable, Equatable, Sendable {
    var aggregation: MetricAggregation
    var field: MetricField?

    init(aggregation: MetricAggregation, field: MetricField?) {
        self.aggregation = aggregation
        self.field = field
    }

    static let photoCount = ChartMetric(aggregation: .count, field: nil)
    static let slowShutterShare = ChartMetric(aggregation: .slowShutterShare, field: nil)

    /// Well-formed when an aggregation that needs a field has one, and one
    /// that does not (count, slow-shutter share) has none.
    var isValid: Bool {
        aggregation.needsField ? field != nil : field == nil
    }

    var displayName: String {
        switch aggregation {
        case .count: "Photo count"
        case .slowShutterShare: aggregation.displayName
        default: "\(aggregation.displayName) \(field?.displayName ?? "")"
            .trimmingCharacters(in: .whitespaces)
        }
    }
}
