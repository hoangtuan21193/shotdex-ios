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
            shutterSpeedDisplay: shutter.flatMap(MetadataFormatter.shutterSpeed),
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
        let store = ChartStore(database: database)
        let spec = ChartSpec(
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
        try store.upsert(StatChart(spec: spec, position: 0))

        let loaded = try #require(try store.fetchAllOrdered().first)
        #expect(loaded.spec.title == "Avg ISO by Camera")
        #expect(loaded.spec.kind == .bar)
        #expect(loaded.spec.dimension == .cameraBody)
        #expect(loaded.spec.metric.aggregation == .average)
        #expect(loaded.spec.metric.field == .iso)
        #expect(loaded.spec.filter.matchMode == .any)
        #expect(loaded.spec.topN == 5)
        // Each spec persists its own date scope inside the JSON config.
        #expect(loaded.spec.scope == .custom(1_600_000_000...1_600_086_399))
    }

    /// FS-07 AC-11: a fresh install seeds exactly six charts, in order.
    @Test func seedDefaultsAreTheSixFromFS07() throws {
        let defaults = ChartSpec.defaultSpecs()
        #expect(defaults.map(\.title) == [
            "Top Camera", "Total Photos & Videos", "Equivalent Focal Length",
            "Body + Lens", "Slow Shutter", "Photos per Month",
        ])
        #expect(defaults[0].kind == .bar && defaults[0].dimension == .cameraBody)
        #expect(defaults[1].kind == .kpi && defaults[1].dimension == nil && defaults[1].metric == .photoCount)
        #expect(defaults[2].kind == .bar && defaults[2].dimension == .focalEquivalent)
        #expect(defaults[3].kind == .bar && defaults[3].dimension == .cameraLensPair)
        #expect(defaults[4].kind == .kpi && defaults[4].dimension == nil && defaults[4].metric == .slowShutterShare)
        // Photos per Month: one line per camera body, the top three.
        #expect(defaults[5].kind == .line && defaults[5].dimension == .dateMonth)
        #expect(defaults[5].seriesSplit == .cameraBody && defaults[5].topN == 3)
        #expect(defaults.allSatisfy { $0.metric.isValid })
        #expect(defaults.allSatisfy { $0.scope == .allTime })

        let database = try AppDatabase.makeEmpty()
        let loaded = try ChartStore(database: database).loadCharts(seededGeneration: 0)
        #expect(loaded.charts.map(\.spec.title) == defaults.map(\.title))
        #expect(loaded.seededGeneration == ChartStore.currentSeedGeneration)
    }

    /// FS-07 AC-11: an install seeded with the old two charts gets the other
    /// four appended after whatever it has, once; deleting them afterwards
    /// does not grow them back.
    @Test func existingInstallAppendsFourMissingOnce() throws {
        let database = try AppDatabase.makeEmpty()
        let store = ChartStore(database: database)
        // The old seed, then a chart of the user's own.
        for (index, spec) in ChartSpec.defaultSpecs().prefix(2).enumerated() {
            try store.upsert(StatChart(spec: spec, position: index))
        }
        try store.upsert(StatChart(spec: ChartSpec(title: "Mine", kind: .bar, dimension: .lens), position: 2))

        let first = try store.loadCharts(seededGeneration: 1)
        #expect(first.charts.map(\.spec.title) == [
            "Top Camera", "Total Photos & Videos", "Mine",
            "Equivalent Focal Length", "Body + Lens", "Slow Shutter", "Photos per Month",
        ])
        #expect(first.seededGeneration == 2)

        // Delete the four, open again with the generation remembered: nothing grows back.
        for chart in first.charts.suffix(4) { try store.delete(id: chart.id) }
        let again = try store.loadCharts(seededGeneration: first.seededGeneration)
        #expect(again.charts.map(\.spec.title) == ["Top Camera", "Total Photos & Videos", "Mine"])
    }

    /// FS-07 AC-15: every seeded chart deletes, and opening the dashboard
    /// again with the generation remembered seeds nothing back.
    @Test func deletingEverySeededChartLeavesNone() throws {
        let database = try AppDatabase.makeEmpty()
        let store = ChartStore(database: database)
        let seeded = try store.loadCharts(seededGeneration: 0)
        #expect(seeded.charts.count == 6)

        for chart in seeded.charts { try store.delete(id: chart.id) }
        #expect(try store.fetchAllOrdered().isEmpty)

        let reopened = try store.loadCharts(seededGeneration: seeded.seededGeneration)
        #expect(reopened.charts.isEmpty)
        #expect(reopened.seededGeneration == seeded.seededGeneration)
    }

    /// The flags an install carries map to the generation it went through.
    @Test func seededGenerationReadsTheFlags() throws {
        let suite = "ChartDashboardTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(StatisticsModel.seededGeneration(in: defaults) == 0)
        defaults.set(true, forKey: SettingsKeys.hasSeededStatCharts)
        #expect(StatisticsModel.seededGeneration(in: defaults) == 1)
        defaults.set(true, forKey: SettingsKeys.hasSeededStatChartsV2)
        #expect(StatisticsModel.seededGeneration(in: defaults) == 2)
    }

    /// Body + Lens groups by both columns — two modules of one phone are two
    /// pairs — and a tapped pair drills to that body and that lens.
    @Test func cameraLensPairGroupsAndDrills() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 6.765mm f/1.78"),
            makeRecord(assetId: "a2", camera: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 9mm f/2.8"),
            makeRecord(assetId: "a3", camera: "EOS R6", lens: "RF 85mm, F1.2"),
            makeRecord(assetId: "a4", camera: "EOS R6", lens: "RF 85mm, F1.2"),
            makeRecord(assetId: "a5", camera: "EOS R6", lens: nil),
        ], cursorAssetId: nil)

        let spec = ChartSpec(title: "Pairs", kind: .bar, dimension: .cameraLensPair)
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        let known = data.filter { !$0.isUnknown }
        #expect(known.count == 3)
        #expect(known.first?.label == "EOS R6 · RF 85mm, F1.2")
        #expect(known.first?.value == 2)
        // A row missing the lens is not a pair: it lands in Unknown.
        #expect(data.first { $0.isUnknown }?.value == 1)

        let key = try #require(known.first?.drillKey)
        let criteria = try #require(ChartDimension.cameraLensPair.drillCriteria(key: key))
        #expect(criteria.cameraBodies == ["EOS R6"])
        #expect(criteria.lenses == ["RF 85mm, F1.2"])
        #expect(!ChartDimension.cameraLensPair.splitsSeries)
    }

    /// Slow Shutter: the share of photos slower than 1/equivalent focal
    /// length, rows missing either input outside the denominator.
    @Test func slowShutterShareMetric() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", shutter: 1.0 / 15, equivalent: 50),
            makeRecord(assetId: "a2", camera: "EOS R6", shutter: 1.0 / 250, equivalent: 50),
            makeRecord(assetId: "a3", camera: "EOS R6", shutter: 1.0 / 250, equivalent: 50),
            makeRecord(assetId: "a4", camera: "A6700", shutter: 1.0 / 250, equivalent: 50),
            makeRecord(assetId: "a5", camera: "A6700", shutter: 1.0 / 15, equivalent: nil),
        ], cursorAssetId: nil)

        let kpi = ChartSpec(title: "Slow", kind: .kpi, dimension: nil, metric: .slowShutterShare)
        #expect(try statisticsQueries.chartData(for: kpi, scope: .allTime).first?.value == 25)
        #expect(ChartValueFormatter.string(25, metric: .slowShutterShare) == "25%")

        let byCamera = ChartSpec(title: "Slow by camera", kind: .bar, dimension: .cameraBody, metric: .slowShutterShare)
        let data = try statisticsQueries.chartData(for: byCamera, scope: .allTime)
        #expect(data.first { $0.label == "EOS R6" }.map { abs($0.value - 100.0 / 3) < 0.001 } == true)
        #expect(data.first { $0.label == "A6700" }?.value == 0)

        let byFocal = ChartSpec(title: "Slow by focal", kind: .bar, dimension: .focalEquivalent, metric: .slowShutterShare)
        let binned = try statisticsQueries.chartData(for: byFocal, scope: .allTime)
        #expect(binned.contains { $0.value == 25 })

        #expect(ChartMetric.slowShutterShare.isValid)
        #expect(!ChartMetric(aggregation: .slowShutterShare, field: .iso).isValid)
        #expect(!ChartKind.donut.allowedAggregations.contains(.slowShutterShare))
    }

    @Test func seedDefaultsOnlyWhenEmpty() throws {
        let database = try AppDatabase.makeEmpty()
        let store = ChartStore(database: database)

        let seeded = try store.seedDefaultsIfEmpty()
        #expect(seeded.count == ChartSpec.defaultSpecs().count)
        #expect(!seeded.isEmpty)

        // Second call is a no-op (does not double up).
        let again = try store.seedDefaultsIfEmpty()
        #expect(again.count == seeded.count)
    }

    @Test func reorderPersistsPositions() throws {
        let database = try AppDatabase.makeEmpty()
        let store = ChartStore(database: database)
        let seeded = try store.seedDefaultsIfEmpty()
        let reversed = seeded.map(\.id).reversed().map { $0 }

        try store.updatePositions(reversed)
        let after = try store.fetchAllOrdered().map(\.id)
        #expect(after == reversed)
    }

    // MARK: Aggregation — categorical

    @Test func categoricalCountWithShares() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "EOS R6"),
            makeRecord(assetId: "a3", camera: "A6700"),
        ], cursorAssetId: nil)

        let spec = ChartSpec(title: "Cameras", kind: .bar, dimension: .cameraBody)
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        #expect(data.first?.label == "EOS R6")
        #expect(data.first?.value == 2)
        #expect(data.first?.drillKey == "EOS R6")
    }

    @Test func categoricalUnknownBucketForCounts() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: nil),
            makeRecord(assetId: "a3", camera: ""),
        ], cursorAssetId: nil)

        let spec = ChartSpec(title: "Cameras", kind: .bar, dimension: .cameraBody)
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        let unknown = data.first { $0.isUnknown }
        #expect(unknown?.value == 2)
        #expect(unknown?.drillKey == nil)
    }

    @Test func categoricalAverageMetric() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", iso: 100),
            makeRecord(assetId: "a2", camera: "EOS R6", iso: 200),
            makeRecord(assetId: "a3", camera: "A6700", iso: 800),
        ], cursorAssetId: nil)

        let spec = ChartSpec(
            title: "Avg ISO", kind: .bar, dimension: .cameraBody,
            metric: ChartMetric(aggregation: .average, field: .iso)
        )
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
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
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", iso: 100),
            makeRecord(assetId: "a2", iso: 3200),
            makeRecord(assetId: "a3", iso: 3200),
        ], cursorAssetId: nil)

        let spec = ChartSpec(title: "ISO", kind: .bar, dimension: .iso)
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        #expect(data.first { $0.label == "≤ 100" }?.value == 1)
        #expect(data.first { $0.label == "1601–6400" }?.value == 2)
        // Every bin is present, labels double as drill keys.
        #expect(data.count == ISOQuickGroup.allCases.count)
        #expect(data.first { $0.label == "≤ 100" }?.drillKey == "≤ 100")
    }

    // MARK: Aggregation — temporal / line

    @Test func temporalLineSplitBySeries() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", creation: 1_700_000_000),
            makeRecord(assetId: "a2", camera: "EOS R6", creation: 1_700_000_000),
            makeRecord(assetId: "a3", camera: "A6700", creation: 1_700_000_000),
        ], cursorAssetId: nil)

        let spec = ChartSpec(
            title: "Trend", kind: .line, dimension: .dateMonth,
            metric: .photoCount, seriesSplit: .cameraBody, topN: 3
        )
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        #expect(!data.isEmpty)
        #expect(data.allSatisfy { $0.series != nil })
        #expect(Set(data.map { $0.series }) == ["EOS R6", "A6700"])
        #expect(data.reduce(0) { $0 + $1.value } == 3)
    }

    // MARK: Aggregation — KPI

    @Test func kpiScalarCountAndMedian() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", iso: 100),
            makeRecord(assetId: "a2", iso: 200),
            makeRecord(assetId: "a3", iso: 300),
        ], cursorAssetId: nil)

        let total = ChartSpec(title: "Total", kind: .kpi, dimension: nil, metric: .photoCount)
        #expect(try statisticsQueries.chartData(for: total, scope: .allTime).first?.value == 3)

        let median = ChartSpec(
            title: "Median ISO", kind: .kpi, dimension: nil,
            metric: ChartMetric(aggregation: .median, field: .iso)
        )
        #expect(try statisticsQueries.chartData(for: median, scope: .allTime).first?.value == 200)
    }

    @Test func kpiTopGroup() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "EOS R6"),
            makeRecord(assetId: "a3", camera: "A6700"),
        ], cursorAssetId: nil)

        let spec = ChartSpec(title: "Top Camera", kind: .kpi, dimension: .cameraBody, metric: .photoCount)
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime)
        #expect(data.count == 1)
        #expect(data.first?.label == "EOS R6")
        #expect(data.first?.value == 2)
    }

    // MARK: Filter + scope

    @Test func specFilterRestrictsPopulation() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        let statisticsQueries = StatisticsQueries(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", favorite: true),
            makeRecord(assetId: "a2", camera: "EOS R6", favorite: false),
            makeRecord(assetId: "a3", camera: "A6700", favorite: true),
        ], cursorAssetId: nil)

        let spec = ChartSpec(
            title: "Favorite cameras", kind: .bar, dimension: .cameraBody,
            filter: SmartAlbumQuery(matchMode: .all, rules: [
                SmartAlbumRule(field: .favorite, boolValue: true),
            ])
        )
        let data = try statisticsQueries.chartData(for: spec, scope: .allTime).filter { !$0.isUnknown }
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
            if let second = dimension.secondGroupColumn {
                #expect(allowed.contains(second), "unexpected column \(second)")
            }
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
