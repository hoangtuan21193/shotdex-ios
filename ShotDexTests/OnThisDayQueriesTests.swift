import Foundation
import Testing
@testable import ShotDex

struct OnThisDayQueriesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second
            )
        )!
    }

    private func epoch(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0
    ) -> Int {
        Int(date(year, month, day, hour: hour, minute: minute, second: second).timeIntervalSince1970)
    }

    /// Local helper rather than the one in `DatabaseTests`: these tests need to
    /// vary `mediaType` and `fileSize`, which that one hard-codes.
    private func makeRow(
        _ assetId: String,
        creation: Int?,
        mediaType: Int = 1,
        fileSize: Int? = 10_000_000
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: creation,
            modificationDate: creation,
            mediaType: mediaType,
            cameraManufacturer: nil,
            cameraModel: nil,
            normalizedCameraModel: nil,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: nil,
            iso: nil,
            aperture: nil,
            shutterSpeedSeconds: nil,
            shutterSpeedDisplay: nil,
            focalLength: nil,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: fileSize,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func makeQueries(_ rows: [PhotoMetadata]) throws -> OnThisDayQueries {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(rows, cursorAssetId: rows.last?.assetId)
        return OnThisDayQueries(database: database)
    }

    // MARK: Counting

    @Test func talliesCountPreviousYearsOnly() throws {
        let queries = try makeQueries([
            makeRow("a1", creation: epoch(2025, 7, 28)),
            makeRow("a2", creation: epoch(2024, 7, 28)),
            // Same month/day in the current year: On This Day is about previous
            // years, so this must not be counted.
            makeRow("a3", creation: epoch(2026, 7, 28)),
            makeRow("a4", creation: epoch(2025, 7, 27)),
        ])
        let tallies = try queries.tallies(
            for: [date(2026, 7, 28, hour: 0)], calendar: calendar, now: date(2026, 7, 28)
        )
        #expect(tallies.count == 1)
        #expect(tallies[0].photoCount == 2)
    }

    @Test func talliesIncludeVideosAndExcludeOtherMediaTypes() throws {
        let queries = try makeQueries([
            makeRow("image", creation: epoch(2025, 7, 28), mediaType: 1),
            makeRow("video", creation: epoch(2025, 7, 28), mediaType: 2),
            makeRow("audio", creation: epoch(2025, 7, 28), mediaType: 3),
        ])
        let tallies = try queries.tallies(
            for: [date(2026, 7, 28, hour: 0)], calendar: calendar, now: date(2026, 7, 28)
        )
        #expect(tallies[0].photoCount == 2)
    }

    @Test func talliesRespectLocalDayBoundaries() throws {
        let queries = try makeQueries([
            makeRow("before", creation: epoch(2025, 7, 27, hour: 23, minute: 59, second: 59)),
            makeRow("first", creation: epoch(2025, 7, 28, hour: 0, minute: 0, second: 0)),
            makeRow("last", creation: epoch(2025, 7, 28, hour: 23, minute: 59, second: 59)),
            makeRow("after", creation: epoch(2025, 7, 29, hour: 0, minute: 0, second: 0)),
        ])
        let tallies = try queries.tallies(
            for: [date(2026, 7, 28, hour: 0)], calendar: calendar, now: date(2026, 7, 28)
        )
        #expect(tallies[0].photoCount == 2)
    }

    // MARK: Sizes

    @Test func sumCoversOnlyRowsThatHaveAFileSize() throws {
        let queries = try makeQueries([
            makeRow("sized1", creation: epoch(2025, 7, 28), fileSize: 3_000_000),
            makeRow("sized2", creation: epoch(2024, 7, 28), fileSize: 4_000_000),
            // Placeholder row written by the fast pass: counted, not measured.
            makeRow("unsized", creation: epoch(2023, 7, 28), fileSize: nil),
        ])
        let tally = try queries.tallies(
            for: [date(2026, 7, 28, hour: 0)], calendar: calendar, now: date(2026, 7, 28)
        )[0]
        #expect(tally.photoCount == 3)
        #expect(tally.sizedPhotoCount == 2)
        #expect(tally.indexedByteCount == 7_000_000)
        #expect(!tally.hasCompleteSize)
        #expect(!tally.hasNoSize)
    }

    @Test func fullyMeasuredDayReportsACompleteSize() throws {
        let queries = try makeQueries([
            makeRow("a", creation: epoch(2025, 7, 28), fileSize: 1_000),
            makeRow("b", creation: epoch(2024, 7, 28), fileSize: 2_000),
        ])
        let tally = try queries.tallies(
            for: [date(2026, 7, 28, hour: 0)], calendar: calendar, now: date(2026, 7, 28)
        )[0]
        #expect(tally.hasCompleteSize)
        #expect(tally.indexedByteCount == 3_000)
    }

    // MARK: Shape of the result

    @Test func emptyDayStillGetsAnEntry() throws {
        let queries = try makeQueries([makeRow("a", creation: epoch(2025, 7, 28))])
        let days = [date(2026, 7, 28, hour: 0), date(2026, 7, 29, hour: 0)]
        let tallies = try queries.tallies(for: days, calendar: calendar, now: date(2026, 7, 28))
        #expect(tallies.count == days.count)
        #expect(tallies.map(\.date) == days)
        #expect(tallies[1].photoCount == 0)
        #expect(tallies[1].hasNoSize)
    }

    @Test func fullHorizonReturnsOneOrderedEntryPerDay() throws {
        let queries = try makeQueries([makeRow("a", creation: epoch(2025, 7, 30))])
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 9 * 60, calendar: calendar, now: date(2026, 7, 28, hour: 6)
        )
        let tallies = try queries.tallies(for: days, calendar: calendar, now: date(2026, 7, 28, hour: 6))
        #expect(tallies.count == days.count)
        #expect(tallies.map(\.date) == days)
        #expect(tallies.filter { $0.photoCount > 0 }.map(\.date) == [date(2026, 7, 30, hour: 0)])
    }

    @Test func noDaysRequestedReturnsNothing() throws {
        let queries = try makeQueries([makeRow("a", creation: epoch(2025, 7, 28))])
        #expect(try queries.tallies(for: [], calendar: calendar, now: date(2026, 7, 28)).isEmpty)
    }

    // MARK: Earliest year

    @Test func earliestCreationYearIgnoresRowsWithoutACreationDate() throws {
        let queries = try makeQueries([
            makeRow("undated", creation: nil),
            makeRow("oldest", creation: epoch(2019, 3, 5)),
            makeRow("newer", creation: epoch(2025, 7, 28)),
        ])
        #expect(try queries.earliestCreationYear(calendar: calendar) == 2019)
    }

    @Test func earliestCreationYearIsNilOnAnEmptyIndex() throws {
        let queries = try makeQueries([])
        #expect(try queries.earliestCreationYear(calendar: calendar) == nil)
    }
}
