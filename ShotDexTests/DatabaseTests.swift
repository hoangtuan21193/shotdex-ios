import Foundation
import Testing
@testable import ShotDex

struct DatabaseTests {

    private func makeRecord(
        assetId: String,
        camera: String? = nil,
        brand: String? = nil,
        lens: String? = nil,
        filename: String? = nil,
        iso: Int? = nil,
        aperture: Double? = nil,
        shutter: Double? = nil,
        focal: Double? = nil,
        equivalent: Double? = nil,
        format: String? = nil,
        creation: Int? = 1_700_000_000,
        favorite: Bool = false,
        status: ExifStatus = .indexed
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: creation,
            modificationDate: creation,
            mediaType: 1,
            cameraManufacturer: brand,
            cameraModel: camera,
            normalizedCameraModel: camera,
            normalizedCameraManufacturer: brand,
            lensManufacturer: nil,
            lensModel: lens,
            normalizedLensModel: lens,
            originalFilename: filename,
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
            exifStatus: status.rawValue
        )
    }

    @Test func migrationCreatesSchema() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        #expect(try dao.indexedCount() == 0)
        #expect(try dao.indexState() == .initial)
    }

    @Test func batchSaveAndCursor() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        let records = (1...5).map { makeRecord(assetId: "a\($0)") }
        try dao.saveBatch(records, cursorAssetId: "a5")
        #expect(try dao.indexedCount() == 5)
        #expect(try dao.indexState().cursorAssetId == "a5")

        // Upsert same batch — no duplicates.
        try dao.saveBatch(records, cursorAssetId: "a5")
        #expect(try dao.indexedCount() == 5)
    }

    @Test func deleteAssetsAndClearAll() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        try dao.saveBatch((1...3).map { makeRecord(assetId: "a\($0)") }, cursorAssetId: nil)
        try dao.deleteAssets(ids: ["a1", "a2"])
        #expect(try dao.indexedCount() == 1)
        try dao.deleteAll()
        #expect(try dao.indexedCount() == 0)
        #expect(try dao.indexState().cursorAssetId == nil)
    }

    @Test func filterByCameraAndISORange() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", brand: "Canon", iso: 100),
            makeRecord(assetId: "a2", camera: "EOS R6", brand: "Canon", iso: 3200),
            makeRecord(assetId: "a3", camera: "A6700", brand: "Sony", iso: 3200),
        ], cursorAssetId: nil)

        var criteria = FilterCriteria()
        criteria.cameraBodies = ["EOS R6"]
        #expect(try queryDAO.count(matching: criteria) == 2)

        criteria.isoRange = NumericRangeFilter(lowerBound: 1601, upperBound: 6400)
        let matches = try await queryDAO.gridItems(matching: criteria, sort: .default)
        #expect(matches.map(\.assetId) == ["a2"])
    }

    @Test func searchTextMatchesCameraAndLens() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", lens: "RF 100-500mm F4.5-7.1 L IS USM"),
            makeRecord(assetId: "a2", camera: "A6700", lens: "FE 24-70mm F2.8 GM"),
        ], cursorAssetId: nil)

        var criteria = FilterCriteria()
        criteria.searchText = "100-500"
        #expect(try queryDAO.count(matching: criteria) == 1)

        criteria.searchText = "r6"
        #expect(try queryDAO.count(matching: criteria) == 1)
    }

    @Test func searchTextMatchesFilename() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", filename: "IMG_1234.HEIC"),
            makeRecord(assetId: "a2", camera: "A6700", filename: "DSC05000.ARW"),
            makeRecord(assetId: "a3", camera: "X-T5", filename: nil),
        ], cursorAssetId: nil)

        var criteria = FilterCriteria()
        // Free-text term (has letters) matches filename case-insensitively.
        criteria.searchText = "img_1234"
        #expect(try queryDAO.count(matching: criteria) == 1)

        criteria.searchText = "DSC0"
        #expect(try queryDAO.count(matching: criteria) == 1)

        // Bare numeric fragment also matches a filename.
        criteria.searchText = "5000"
        #expect(try queryDAO.count(matching: criteria) == 1)

        // Row with nil filename is never matched by a filename query.
        criteria.searchText = "nonexistent"
        #expect(try queryDAO.count(matching: criteria) == 0)
    }

    @Test func sortOrders() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", iso: 100, creation: 100),
            makeRecord(assetId: "a2", iso: 3200, creation: 200),
            makeRecord(assetId: "a3", iso: nil, creation: 300),
        ], cursorAssetId: nil)

        let newest = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: .dateTakenNewest)
        #expect(newest.map(\.assetId) == ["a3", "a2", "a1"])

        let isoHigh = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: .isoDescending)
        #expect(isoHigh.map(\.assetId) == ["a2", "a1", "a3"])
    }

    @Test func distinctValueLists() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", brand: "Canon", lens: "RF 50mm F1.8 STM"),
            makeRecord(assetId: "a2", camera: "EOS R6", brand: "Canon", lens: "RF 50mm F1.8 STM"),
            makeRecord(assetId: "a3", camera: "A6700", brand: "Sony"),
        ], cursorAssetId: nil)

        #expect(try queryDAO.distinctCameraBrands() == ["Canon", "Sony"])
        #expect(try queryDAO.distinctCameraBodies() == ["A6700", "EOS R6"])
        #expect(try queryDAO.distinctLenses() == ["RF 50mm F1.8 STM"])
    }

    @Test func statsAggregates() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", lens: "RF 50mm", focal: 50, equivalent: 50, format: "Full Frame"),
            makeRecord(assetId: "a2", camera: "EOS R6", lens: "RF 50mm", focal: 50, equivalent: 50, format: "Full Frame"),
            makeRecord(assetId: "a3", camera: "OM-1", lens: "12-40mm", focal: 25, equivalent: 50, format: "Micro Four Thirds"),
        ], cursorAssetId: nil)

        #expect(try statsDAO.totalPhotos(scope: .allTime) == 3)

        let cameras = try statsDAO.cameraUsage(scope: .allTime)
        #expect(cameras.first?.name == "EOS R6")
        #expect(cameras.first?.count == 2)
        #expect(cameras.first.map { abs($0.percentage - 66.66) < 1 } == true)

        let summary = try statsDAO.summary(scope: .allTime)
        #expect(summary.totalPhotos == 3)
        #expect(summary.mostUsedCamera == "EOS R6")
        #expect(summary.mostUsedFocalLength == 50)
        #expect(summary.mostUsedSensorFormat == .fullFrame)

        let histogram = try statsDAO.focalLengthHistogram(equivalent: true, scope: .allTime)
        let bucket50 = histogram.first { $0.label == "50–69" }
        #expect(bucket50?.count == 3)
    }

    @Test func indexedAssetStatesAndRetryableIds() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        try dao.saveBatch([
            makeRecord(assetId: "a1", status: .indexed),
            makeRecord(assetId: "a2", status: .pendingICloud),
            makeRecord(assetId: "a3", status: .error),
            makeRecord(assetId: "a4", status: .noExif),
        ], cursorAssetId: nil)

        let states = try dao.indexedAssetStates()
        #expect(states.count == 4)
        #expect(states["a2"] == IndexedAssetState(
            modificationDate: 1_700_000_000,
            exifStatus: ExifStatus.pendingICloud.rawValue
        ))
        #expect(Set(try dao.retryableAssetIds()) == ["a2", "a3"])
    }

    @Test func usageIncludesUnknownBucketWithFullScopePercentages() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "EOS R6"),
            makeRecord(assetId: "a3", camera: nil, status: .pendingICloud),
            makeRecord(assetId: "a4", camera: ""),
        ], cursorAssetId: nil)

        let cameras = try statsDAO.cameraUsage(scope: .allTime)
        // NULL and empty-string cameras fold into one Unknown bucket.
        let unknown = cameras.first { $0.isUnknown }
        #expect(unknown?.name == "Unknown")
        #expect(unknown?.count == 2)
        // Buckets cover the whole library and percentages sum to ~100.
        #expect(cameras.reduce(0) { $0 + $1.count } == 4)
        #expect(abs(cameras.reduce(0.0) { $0 + $1.percentage } - 100) < 0.01)
        // Percentages are shares of ALL photos even with a LIMIT.
        let top = try statsDAO.usage(groupedBy: "normalizedCameraModel", scope: .allTime, limit: 1)
        #expect(top.first?.percentage == 50)
        // Most Used Camera never reports the Unknown bucket.
        let summary = try statsDAO.summary(scope: .allTime)
        #expect(summary.mostUsedCamera == "EOS R6")
    }

    @Test func sensorFormatUsageMergesNullIntoUnknown() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", format: "Full Frame"),
            makeRecord(assetId: "a2", format: SensorFormat.unknown.rawValue),
            makeRecord(assetId: "a3", format: nil, status: .pendingICloud),
        ], cursorAssetId: nil)

        let formats = try statsDAO.sensorFormatUsage(scope: .allTime)
        #expect(formats.count == 2)
        let unknown = formats.first { $0.isUnknown }
        #expect(unknown?.name == SensorFormat.unknown.rawValue)
        #expect(unknown?.count == 2)
        #expect(formats.reduce(0) { $0 + $1.count } == 3)
    }

    @Test func undatedPhotosCountedAndExcludedFromScopedStats() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let statsDAO = StatsDAO(database: database)
        let now = Int(Date().timeIntervalSince1970)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", creation: now - 60),
            makeRecord(assetId: "a2", creation: nil),
            makeRecord(assetId: "a3", creation: nil),
        ], cursorAssetId: nil)

        #expect(try statsDAO.undatedCount() == 2)
        #expect(try statsDAO.totalPhotos(scope: .allTime) == 3)
        // NULL creationDate never matches a BETWEEN scope.
        #expect(try statsDAO.totalPhotos(scope: .custom((now - 3600)...now)) == 1)
    }

    @Test func gridItemsCompleteAndDeterministicWithTiedAndNullDates() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        // 10 rows sharing one creationDate + 3 rows without a date: ties
        // would make the display order nondeterministic without the
        // assetId tiebreaker.
        var records = (1...10).map { makeRecord(assetId: "tied\($0)", creation: 500) }
        records += (1...3).map { makeRecord(assetId: "null\($0)", creation: nil) }
        try metadataDAO.saveBatch(records, cursorAssetId: nil)

        for sort in SortOption.allCases {
            let rows = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: sort)
            let seen = rows.map(\.assetId)
            #expect(seen.count == 13, "sort \(sort) dropped rows")
            #expect(Set(seen).count == 13, "sort \(sort) returned duplicates")
            // Deterministic: same query, same order.
            let again = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: sort)
            #expect(again.map(\.assetId) == seen, "sort \(sort) order unstable")
        }
        // NULLS LAST: undated rows always trail on date sorts.
        let newest = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: .dateTakenNewest)
        #expect(Set(newest.suffix(3).map(\.assetId)) == ["null1", "null2", "null3"])
    }

    @Test func gridItemsProjectionRoundTrip() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", iso: 3200, aperture: 2.8, shutter: 0.002, focal: 85, equivalent: 85, creation: 1_700_000_000),
        ], cursorAssetId: nil)

        let rows = try await queryDAO.gridItems(matching: FilterCriteria.empty, sort: .default)
        let item = try #require(rows.first)
        #expect(item.assetId == "a1")
        #expect(item.creationDate == 1_700_000_000)
        #expect(item.iso == 3200)
        #expect(item.aperture == 2.8)
        #expect(item.shutterSpeedDisplay == FormatUtils.shutterSpeed(0.002))
        #expect(item.focalLength == 85)
        #expect(item.equivalentFocalLength == 85)
        let total = try queryDAO.count(matching: FilterCriteria.empty)
        #expect(rows.count == total)
    }

    @Test func metadataByIdAndBatch() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6"),
            makeRecord(assetId: "a2", camera: "A6700"),
        ], cursorAssetId: nil)

        #expect(try queryDAO.metadata(assetId: "a1")?.normalizedCameraModel == "EOS R6")
        #expect(try queryDAO.metadata(assetId: "missing") == nil)

        let batch = try queryDAO.metadata(assetIds: ["a1", "a2", "missing"])
        #expect(Set(batch.keys) == ["a1", "a2"])
        #expect(try queryDAO.metadata(assetIds: []).isEmpty)
    }

    /// The lazy badge fill re-reads a tile's row on display: a fast-pass
    /// `pendingRead` row must come back non-final (no caching), and the
    /// upsert to `indexed` must be what the next read sees.
    @Test func metadataByIdSeesPendingToIndexedUpgrade() throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)

        try metadataDAO.saveBatch(
            [makeRecord(assetId: "a1", status: .pendingRead)], cursorAssetId: nil
        )
        let pending = try queryDAO.metadata(assetId: "a1")
        #expect(pending?.resolvedExifStatus == .pendingRead)
        #expect(GridBadgeCache.entry(for: pending) == nil)

        try metadataDAO.saveBatch(
            [makeRecord(assetId: "a1", iso: 800, status: .indexed)], cursorAssetId: nil
        )
        let upgraded = try queryDAO.metadata(assetId: "a1")
        #expect(upgraded?.resolvedExifStatus == .indexed)
        guard case .badge(let item)? = GridBadgeCache.entry(for: upgraded) else {
            Issue.record("expected .badge after upgrade")
            return
        }
        #expect(item.iso == 800)
    }

    @Test func everySortOrderEndsWithUniqueTiebreaker() {
        for sort in SortOption.allCases {
            #expect(LibraryQueryDAO.orderClause(for: sort).hasSuffix("assetId ASC"))
        }
    }

    @Test func resolveUnknownCamerasRewritesOnlyCoveredModels() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        try dao.saveBatch([
            makeRecord(assetId: "a1", camera: "ILCE-7M2", focal: 50, format: SensorFormat.unknown.rawValue),
            makeRecord(assetId: "a2", camera: "Mystery Cam", format: SensorFormat.unknown.rawValue),
        ], cursorAssetId: nil)

        let lookup = SensorLookup(records: [
            SensorCameraRecord(manufacturer: "Sony", model: "A7 II", sensorFormat: "Full Frame", cropFactor: 1.0, aliases: ["ILCE-7M2"])
        ])
        #expect(try dao.resolveUnknownCameras(using: lookup) == 1)
        #expect(try dao.unknownCameraModels() == ["Mystery Cam"])

        let resolved = try LibraryQueryDAO(database: database).metadata(assetId: "a1")
        #expect(resolved?.sensorFormat == "Full Frame")
        #expect(resolved?.cropFactor == 1.0)
        #expect(resolved?.equivalentFocalLength == 50)
        // A second pass finds nothing left to do.
        #expect(try dao.resolveUnknownCameras(using: lookup) == 0)
    }

    @Test func customMappingRoundTrip() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = MetadataDAO(database: database)
        try dao.saveCustomMapping(CustomCameraMapping(normalizedCameraModel: "Cam X", sensorFormat: "APS-C", cropFactor: 1.5))
        #expect(try dao.customMappings().count == 1)
        try dao.deleteAllCustomMappings()
        #expect(try dao.customMappings().isEmpty)
    }

    // MARK: Smart album persistence + rule queries

    @Test func smartAlbumRulesSurvivePersistence() throws {
        let database = try AppDatabase.makeEmpty()
        let dao = SmartAlbumDAO(database: database)

        let query = SmartAlbumQuery(matchMode: .any, rules: [
            SmartAlbumRule(field: .cameraBody, op: .contains, text: "R6"),
            SmartAlbumRule(field: .iso, op: .greaterThan, number: 1600),
        ])
        // Pure Codable round-trip (no GRDB) to isolate init(from:).
        let data = try JSONEncoder().encode(query)
        let back = try JSONDecoder().decode(SmartAlbumQuery.self, from: data)
        #expect(back.matchMode == .any)
        #expect(back.rules.count == 2)

        try dao.upsert(SmartAlbum(id: "s1", name: "Test", query: query, createdAt: 1))

        let loaded = try #require(try dao.fetchAllOrdered().first)
        #expect(loaded.query.matchMode == .any)
        #expect(loaded.query.rules.count == 2)
        #expect(loaded.query.rules.first?.text == "R6")
        #expect(loaded.query.rules.last?.number == 1600)
    }

    @Test func smartAlbumQueryFiltersNotFullLibrary() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadataDAO = MetadataDAO(database: database)
        let queryDAO = LibraryQueryDAO(database: database)
        try metadataDAO.saveBatch([
            makeRecord(assetId: "a1", camera: "EOS R6", brand: "Canon", iso: 100),
            makeRecord(assetId: "a2", camera: "EOS R6", brand: "Canon", iso: 3200),
            makeRecord(assetId: "a3", camera: "A6700", brand: "Sony", iso: 3200),
        ], cursorAssetId: nil)

        let query = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .cameraBody, op: .contains, text: "R6"),
        ])
        #expect(try queryDAO.count(matching: query) == 2)
        let items = try await queryDAO.gridItems(matching: query, sort: .default)
        #expect(items.map(\.assetId).sorted() == ["a1", "a2"])
    }
}
