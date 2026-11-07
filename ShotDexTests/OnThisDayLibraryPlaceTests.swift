import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The Mac's On This Day place (FS-18.04 §1.1): which ids the place shows,
/// and the place named in each year's header.
struct OnThisDayLibraryPlaceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func epoch(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Int {
        Int(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!.timeIntervalSince1970)
    }

    private func now(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func row(_ assetId: String, creation: Int) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId, creationDate: creation, modificationDate: creation, mediaType: 1,
            cameraManufacturer: nil, cameraModel: nil, normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil, iso: nil,
            aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil, focalLength: nil, focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil, sensorFormat: nil, cropFactor: nil,
            width: 6000, height: 4000, fileSize: 1, latitude: nil, longitude: nil, isFavorite: false,
            indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func makeQueries(_ rows: [PhotoMetadata]) throws -> LibraryQueries {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(rows, cursorAssetId: rows.last?.assetId)
        return LibraryQueries(database: database)
    }

    @Test func showsTheDayInEarlierYearsOnly() async throws {
        let queries = try makeQueries([
            row("2021", creation: epoch(2021, 10, 4)),
            row("2025-late", creation: epoch(2025, 10, 4, hour: 23, minute: 59)),
            row("2025-next", creation: epoch(2025, 10, 5, hour: 0, minute: 1)),
            row("this-year", creation: epoch(2026, 10, 4)),
        ])
        let ids = try await queries.assetIdsOnThisDay(month: 10, day: 4, calendar: calendar, now: now(2026, 11, 7))
        #expect(Set(ids) == ["2021", "2025-late"])
    }

    @Test func februaryTwentyNinthFindsLeapYears() async throws {
        let queries = try makeQueries([
            row("2024", creation: epoch(2024, 2, 29)),
            row("2023-mar1", creation: epoch(2023, 3, 1)),
        ])
        // Asked in a year with no Feb 29 of its own.
        let ids = try await queries.assetIdsOnThisDay(month: 2, day: 29, calendar: calendar, now: now(2026, 11, 7))
        #expect(ids == ["2024"])
    }

    @Test func eraCalendarStillFindsTheDay() async throws {
        let queries = try makeQueries([row("2021", creation: epoch(2021, 10, 4)), row("2024-leap", creation: epoch(2024, 2, 29))])
        // A Japanese era year (Reiwa 8) is smaller than the photos' years in Heisei/Reiwa terms.
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = calendar.timeZone
        let october = try await queries.assetIdsOnThisDay(month: 10, day: 4, calendar: japanese, now: now(2026, 11, 7))
        #expect(october == ["2021"])
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        let leap = try await queries.assetIdsOnThisDay(month: 2, day: 29, calendar: buddhist, now: now(2026, 11, 7))
        #expect(leap == ["2024-leap"])
    }

    @Test func onThisDayKeepsDateOrder() {
        #expect(LibraryPlace.onThisDay(month: 10, day: 4).fixedSort == .dateTakenNewest)
        #expect(LibraryPlace.favorites.fixedSort == nil)
    }

    @Test func emptyLibraryHasNothing() async throws {
        let queries = try makeQueries([])
        let ids = try await queries.assetIdsOnThisDay(month: 10, day: 4, calendar: calendar, now: now(2026, 11, 7))
        #expect(ids.isEmpty)
    }

    @Test func eachYearNamesItsCommonestPlace() async throws {
        let queries = try makeQueries([
            row("a", creation: epoch(2021, 10, 4)), row("b", creation: epoch(2021, 10, 4)),
            row("c", creation: epoch(2021, 10, 4)), row("d", creation: epoch(2023, 10, 4)),
        ])
        try await queries.database.writer.write { db in
            for (id, town, country) in [("a", "Hanoi", "Vietnam"), ("b", "Hanoi", "Vietnam"), ("c", "Hue", "Vietnam")] {
                try db.execute(sql: "UPDATE photo_metadata SET placeLocality = ?, placeCountry = ? WHERE assetId = ?",
                               arguments: [town, country, id])
            }
        }
        let places = try await queries.placesByYear(ids: ["a", "b", "c", "d"], calendar: calendar)
        #expect(places == [2021: "Hanoi, Vietnam"])
    }
}
