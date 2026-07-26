import Foundation
import Testing
@testable import ShotDex

/// Statistics dashboard: chart persistence, aggregation engine, validity
/// matrix, and the closed-enum→column mapping that keeps SQL injection-free.
struct ChartDashboardTests {

    private func makeRecord(
        assetId: String,
        camera: String? = nil,
        lens: String? = nil,
        iso: Int? = nil,
        aperture: Double? = nil,
        shutter: Double? = nil,
        focal: Double? = nil,
        equivalent: Double? = nil,
        format: String? = nil,
        creation: Int? = 1_700_000_000,
        favorite: Bool = false
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: creation,
            modificationDate: creation,
            mediaType: 1,
            cameraManufacturer: nil,
            cameraModel: camera,
            normalizedCameraModel: camera,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: lens,
            normalizedLensModel: lens,
            originalFilename: nil,
            iso: iso,
            aperture: aperture,
            shutterSpeedSeconds: shutter,
            shutterSpeedDisplay: shutter.flatMap(FormatUtils.shutterSpeed),
            focalLength: focal,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: equivalent,
            equivalentFocalLength: equivalent,
            sensorFormat: format,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: 10_000_000,
            latitude: nil,
            longitude: nil,
            isFavorite: favorite,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    // MARK: Persistence

    @Test func statChartConfigRoundTrips() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = StatChartDAO(database: database)
        let widget = ChartWidget(
            id: "c1",
            title: "Avg ISO by Camera",
            kind: .bar,
            dimension: .cameraBody,
            metric: ChartMetric(aggregation: .average, field: .iso),
            filter: SmartAlbumQuery(matchMode: .any, rules: [
                SmartAlbumRule(field: .favorite, boolValue: true),
            ]),
            topN: 5,
            scope: .custom(1_600_000_000...1_600_086_399)
        )
        try dao.upsert(StatChart(widget: widget, position: 0))

        let loaded = try #require(try dao.fetchAllOrdered().first)
        #expect(loaded.widget.title == "Avg ISO by Camera")
        #expect(loaded.widget.kind == .bar)
        #expect(loaded.widget.dimension == .cameraBody)
        #expect(loaded.widget.metric.aggregation == .average)
        #expect(loaded.widget.metric.field == .iso)
        #expect(loaded.widget.filter.matchMode == .any)
        #expect(loaded.widget.topN == 5)
        // Each widget persists its own date scope inside the JSON config.
        #expect(loaded.widget.scope == .custom(1_600_000_000...1_600_086_399))
    }

    @Test func seedDefaultsAreTopCameraAndTotal() throws {
        let defaults = ChartWidget.defaultWidgets()
        #expect(defaults.count == 2)
        #expect(defaults[0].kind == .bar)
        #expect(defaults[0].dimension == .cameraBody)
        #expect(defaults[1].kind == .kpi)
        #expect(defaults[1].dimension == nil)
        #expect(defaults[1].metric == .photoCount)
        // Scope defaults to all time.
        #expect(defaults.allSatisfy { $0.scope == .allTime })
    }

    @Test func seedDefaultsOnlyWhenEmpty() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = StatChartDAO(database: database)

        let seeded = try dao.seedDefaultsIfEmpty()
        #expect(seeded.count == ChartWidget.defaultWidgets().count)
        #expect(!seeded.isEmpty)

        // Second call is a no-op (does not double up).
        let again = try dao.seedDefaultsIfEmpty()
        #expect(again.count == seeded.count)
    }

    @Test func reorderPersistsPositions() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = StatChartDAO(database: database)
        let seeded = try dao.seedDefaultsIfEmpty()
        let reversed = seeded.map(\.id).reversed().map { $0 }

        try dao.updatePositions(reversed)
        let after = try dao.fetchAllOrdered().map(\.id)
        #expect(after == reversed)
    }

    // MARK: Aggregation — categorical

    @Test func categoricalCountWithShares() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "EOS R6"),
            makeRecord(assetId: "a3", camera: "A6700"),
        ], cursorAssetId: nil)

        let widget = ChartWidget(title: "Cameras", kind: .bar, dimension: .cameraBody)
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        #expect(data.first?.label == "EOS R6")
        #expect(data.first?.value == 2)
        #expect(data.first?.drillKey == "EOS R6")
    }

    @Test func categoricalUnknownBucketForCounts() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: nil),
            makeRecord(assetId: "a3", camera: ""),
        ], cursorAssetId: nil)

        let widget = ChartWidget(title: "Cameras", kind: .bar, dimension: .cameraBody)
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        let unknown = data.first { $0.isUnknown }
        #expect(unknown?.value == 2)
        #expect(unknown?.drillKey == nil)
    }

    @Test func categoricalAverageMetric() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", iso: 100),
            makeRecord(assetId: "a2", camera: "EOS R6", iso: 200),
            makeRecord(assetId: "a3", camera: "A6700", iso: 800),
        ], cursorAssetId: nil)

        let widget = ChartWidget(
            title: "Avg ISO", kind: .bar, dimension: .cameraBody,
            metric: ChartMetric(aggregation: .average, field: .iso)
        )
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        // Sorted by value DESC: A6700 (800) then EOS R6 (150).
        #expect(data.first?.label == "A6700")
        #expect(data.first?.value == 800)
        #expect(data.last?.value == 150)
        // Aggregates carry no Unknown bucket.
        #expect(!data.contains { $0.isUnknown })
    }

    // MARK: Aggregation — binned

    @Test func binnedIsoHistogram() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", iso: 100),
            makeRecord(assetId: "a2", iso: 3200),
            makeRecord(assetId: "a3", iso: 3200),
        ], cursorAssetId: nil)

        let widget = ChartWidget(title: "ISO", kind: .bar, dimension: .iso)
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        #expect(data.first { $0.label == "≤ 100" }?.value == 1)
        #expect(data.first { $0.label == "1601–6400" }?.value == 2)
        // Every bin is present, labels double as drill keys.
        #expect(data.count == ISOQuickGroup.allCases.count)
        #expect(data.first { $0.label == "≤ 100" }?.drillKey == "≤ 100")
    }

    // MARK: Aggregation — temporal / line

    @Test func temporalLineSplitBySeries() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", creation: 1_700_000_000),
            makeRecord(assetId: "a2", camera: "EOS R6", creation: 1_700_000_000),
            makeRecord(assetId: "a3", camera: "A6700", creation: 1_700_000_000),
        ], cursorAssetId: nil)

        let widget = ChartWidget(
            title: "Trend", kind: .line, dimension: .dateMonth,
            metric: .photoCount, seriesSplit: .cameraBody, topN: 3
        )
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        #expect(!data.isEmpty)
        #expect(data.allSatisfy { $0.series != nil })
        #expect(Set(data.map { $0.series }) == ["EOS R6", "A6700"])
        #expect(data.reduce(0) { $0 + $1.value } == 3)
    }

    // MARK: Aggregation — KPI

    @Test func kpiScalarCountAndMedian() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", iso: 100),
            makeRecord(assetId: "a2", iso: 200),
            makeRecord(assetId: "a3", iso: 300),
        ], cursorAssetId: nil)

        let total = ChartWidget(title: "Total", kind: .kpi, dimension: nil, metric: .photoCount)
        #expect(try statsDAO.chartData(for: total, scope: .allTime).first?.value == 3)

        let median = ChartWidget(
            title: "Median ISO", kind: .kpi, dimension: nil,
            metric: ChartMetric(aggregation: .median, field: .iso)
        )
        #expect(try statsDAO.chartData(for: median, scope: .allTime).first?.value == 200)
    }

    @Test func kpiTopGroup() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "EOS R6"),
            makeRecord(assetId: "a3", camera: "A6700"),
        ], cursorAssetId: nil)

        let widget = ChartWidget(title: "Top Camera", kind: .kpi, dimension: .cameraBody, metric: .photoCount)
        let data = try statsDAO.chartData(for: widget, scope: .allTime)
        #expect(data.count == 1)
        #expect(data.first?.label == "EOS R6")
        #expect(data.first?.value == 2)
    }

    // MARK: Filter + scope

    @Test func widgetFilterRestrictsPopulation() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", favorite: true),
            makeRecord(assetId: "a2", camera: "EOS R6", favorite: false),
            makeRecord(assetId: "a3", camera: "A6700", favorite: true),
        ], cursorAssetId: nil)

        let widget = ChartWidget(
            title: "Favorite cameras", kind: .bar, dimension: .cameraBody,
            filter: SmartAlbumQuery(matchMode: .all, rules: [
                SmartAlbumRule(field: .favorite, boolValue: true),
            ])
        )
        let data = try statsDAO.chartData(for: widget, scope: .allTime).filter { !$0.isUnknown }
        #expect(data.reduce(0) { $0 + $1.value } == 2)
        #expect(data.first { $0.label == "EOS R6" }?.value == 1)
    }

    // MARK: Validity matrix

    @Test func chartKindValidityMatrix() {
        #expect(ChartKind.donut.allowedAggregations == [.count])
        #expect(!ChartKind.bar.allowedAggregations.contains(.median))
        #expect(!ChartKind.line.allowedAggregations.contains(.median))
        #expect(ChartKind.kpi.allowedAggregations.contains(.median))

        #expect(ChartKind.line.allowedDimensions.allSatisfy { $0.axisKind == .temporal })
        #expect(ChartKind.donut.allowedDimensions.allSatisfy { $0.axisKind == .categorical })
        #expect(ChartKind.bar.allowedDimensions.allSatisfy { $0.axisKind != .temporal })
        #expect(!ChartKind.kpi.requiresDimension)
        #expect(ChartKind.bar.requiresDimension)

        #expect(ChartMetric.photoCount.isValid)
        #expect(ChartMetric(aggregation: .average, field: nil).isValid == false)
        #expect(ChartMetric(aggregation: .count, field: .iso).isValid == false)
    }

    // MARK: Injection guard — columns come only from a fixed allowlist

    @Test func dimensionColumnsAreAllowlisted() {
        let allowed: Set<String> = [
            "normalizedCameraModel", "normalizedCameraManufacturer", "normalizedLensModel",
            "sensorFormat", "isFavorite", "iso", "aperture", "shutterSpeedSeconds",
            "focalLength", "equivalentFocalLength", "creationDate",
        ]
        for dimension in ChartDimension.allCases {
            #expect(allowed.contains(dimension.groupColumn), "unexpected column \(dimension.groupColumn)")
        }
    }

    @Test func metricExpressionsAreAllowlisted() {
        let allowed: Set<String> = [
            "iso", "aperture", "shutterSpeedSeconds", "focalLength",
            "equivalentFocalLength", "fileSize", "(width * 1.0 * height) / 1000000.0",
        ]
        for field in MetricField.allCases {
            #expect(allowed.contains(field.columnExpression), "unexpected expression \(field.columnExpression)")
        }
    }
}
