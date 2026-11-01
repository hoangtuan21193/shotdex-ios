import Foundation
import Testing
@testable import ShotDex

/// The Utilities tab's Statistics card: counts and the last twelve months
/// (in-memory GRDB).
struct StatisticsOverviewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func record(_ id: String, camera: String?, lens: String?, on date: Date) -> PhotoMetadata {
        let creation = Int(date.timeIntervalSince1970)
        return PhotoMetadata(
            assetId: id, creationDate: creation, modificationDate: creation, mediaType: 1,
            cameraManufacturer: nil, cameraModel: camera, normalizedCameraModel: camera,
            normalizedCameraManufacturer: nil, lensManufacturer: nil, lensModel: lens, normalizedLensModel: lens,
            originalFilename: nil, iso: nil, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil, sensorFormat: nil, cropFactor: nil, width: 4000, height: 3000,
            fileSize: 1_000_000, latitude: nil, longitude: nil, isFavorite: false, indexedAt: creation,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    @Test func countsDistinctBodiesAndLensesIgnoringEmpty() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            record("a", camera: "EOS R6", lens: "RF 50mm", on: date(2026, 9)),
            record("b", camera: "EOS R6", lens: "RF 85mm", on: date(2026, 9)),
            record("c", camera: "X100V", lens: nil, on: date(2026, 8)),
            record("d", camera: "", lens: "", on: date(2026, 8)),
        ], cursorAssetId: nil)

        let overview = try StatisticsQueries(database: database).overview(now: date(2026, 10), calendar: calendar)
        #expect(overview.photos == 4)
        #expect(overview.cameras == 2)
        #expect(overview.lenses == 2)
    }

    /// Twelve months ending with the current one, oldest first, empty ones
    /// as zero, and nothing from before the window.
    @Test func monthsCoverTheLastYearWithZeros() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            record("old", camera: nil, lens: nil, on: date(2025, 10)),
            record("nov1", camera: nil, lens: nil, on: date(2025, 11, 2)),
            record("nov2", camera: nil, lens: nil, on: date(2025, 11, 28)),
            record("oct", camera: nil, lens: nil, on: date(2026, 10, 1)),
        ], cursorAssetId: nil)

        let overview = try StatisticsQueries(database: database).overview(now: date(2026, 10, 20), calendar: calendar)
        #expect(overview.months.count == 12)
        #expect(overview.months.first?.start == calendar.dateInterval(of: .month, for: date(2025, 11))?.start)
        #expect(overview.months.first?.count == 2)
        #expect(overview.months.last?.count == 1)
        #expect(overview.months.map(\.count).reduce(0, +) == 3)
        #expect(overview.photos == 4)
    }

    @Test func emptyLibraryHasTwelveZeroMonths() throws {
        let overview = try StatisticsQueries(database: try AppDatabase.makeEmpty()).overview(now: date(2026, 10), calendar: calendar)
        #expect(overview.photos == 0)
        #expect(overview.months.count == 12)
        #expect(overview.months.allSatisfy { $0.count == 0 })
    }
}
