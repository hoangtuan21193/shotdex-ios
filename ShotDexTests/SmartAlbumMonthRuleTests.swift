import Foundation
import Testing
@testable import ShotDex

/// FS-06.08 §2 / FS-07 AC-18: the "in month" smart-album condition — the
/// whole calendar month of the capture date, in local time.
struct SmartAlbumMonthRuleTests {

    private func epoch(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Int {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return Int(date.timeIntervalSince1970)
    }

    private func photo(_ id: String, at creation: Int) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: creation, modificationDate: creation, mediaType: 1,
            cameraManufacturer: nil, cameraModel: "EOS R6", normalizedCameraModel: "EOS R6",
            normalizedCameraManufacturer: nil, lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil,
            originalFilename: nil, iso: nil, aperture: nil, shutterSpeedSeconds: 1.0 / 250, shutterSpeedDisplay: "1/250",
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil, width: 4000, height: 3000, fileSize: 1_000_000,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: creation,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    /// The AC-17 library: 2,140 photos — June 300, July 280, August 1,240,
    /// September 320 (2026), spread over each month's days.
    private func ac17Database() throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        var rows: [PhotoMetadata] = []
        for (month, count) in [(6, 300), (7, 280), (8, 1240), (9, 320)] {
            rows += (0..<count).map { photo("\(month)-\($0)", at: epoch(2026, month, 1 + $0 % 28, $0 % 24)) }
        }
        try MetadataStore(database: database).saveBatch(rows, cursorAssetId: nil)
        return database
    }

    private func monthRule(_ year: Int, _ month: Int) -> SmartAlbumRule {
        SmartAlbumRule(
            field: .dateTaken, op: .inMonth,
            number: CaptureMonth(year: year, month: month).anchorDate().timeIntervalSince1970
        )
    }

    /// AC-18: August 2026 → 1,240; switched to July → 280.
    @Test func monthRuleCountsTheWholeMonth() async throws {
        let queries = LibraryQueries(database: try ac17Database())
        var album = SmartAlbumQuery(matchMode: .all, rules: [monthRule(2026, 8)])
        #expect(try await queries.count(matching: album) == 1240)
        album.rules[0] = monthRule(2026, 7)
        #expect(try await queries.count(matching: album) == 280)
    }

    /// Local time, half-open: 23:30 on the last evening is in the month,
    /// midnight on the first of the next is not.
    @Test func monthEdgesFollowLocalTime() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            photo("first", at: epoch(2026, 8, 1, 0, 0)),
            photo("lastEvening", at: epoch(2026, 8, 31, 23, 30)),
            photo("nextMonth", at: epoch(2026, 9, 1, 0, 0)),
            photo("previousMonth", at: epoch(2026, 7, 31, 23, 59)),
        ], cursorAssetId: nil)
        let album = SmartAlbumQuery(matchMode: .all, rules: [monthRule(2026, 8)])
        #expect(try await LibraryQueries(database: database).count(matching: album) == 2)
    }

    @Test func monthRuleValidityAndOperatorMenu() {
        #expect(RuleFieldKind.date.allowedOperators.contains(.inMonth))
        #expect(RuleFieldKind.date.allowedOperators.firstIndex(of: .inMonth) == 1, "right after 'is on'")
        #expect(!SmartAlbumRule(field: .dateTaken, op: .inMonth).isValid)
        #expect(monthRule(2026, 8).isValid)
        // The stored instant names its month in every time zone ±14h.
        let anchor = CaptureMonth(year: 2026, month: 8).anchorDate()
        for hours in [-14, -7, 0, 7, 14] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: hours * 3600)!
            #expect(CaptureMonth(containing: anchor, calendar: calendar) == CaptureMonth(year: 2026, month: 8))
        }
        #expect(CaptureMonth(year: 2026, month: 8).abbreviatedName(locale: Locale(identifier: "en_US")) == "Aug 2026")
    }

    /// A rule this build cannot read is dropped on its own; the album keeps
    /// its month condition (decode stays lossy).
    @Test func unknownOperatorDropsOnlyThatRule() throws {
        let month = monthRule(2026, 8)
        let json = """
        {"matchMode":"all","rules":[
          {"id":"\(UUID().uuidString)","field":"dateTaken","op":"inFortnight","text":"","number":1,"boolValue":true,"focalMode":"actual"},
          \(String(decoding: try JSONEncoder().encode(month), as: UTF8.self))
        ]}
        """
        let decoded = try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))
        #expect(decoded.rules.count == 1)
        #expect(decoded.rules.first?.op == .inMonth)
        #expect(decoded.rules.first?.number == month.number)
    }
}
