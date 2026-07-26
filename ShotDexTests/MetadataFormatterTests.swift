import Foundation
import Testing
@testable import ShotDex

struct MetadataFormatterTests {

    @Test func shutterSpeedFormatting() {
        #expect(MetadataFormatter.shutterSpeed(1.0 / 500.0) == "1/500s")
        #expect(MetadataFormatter.shutterSpeed(1.0 / 30.0) == "1/30s")
        #expect(MetadataFormatter.shutterSpeed(2.0) == "2s")
        #expect(MetadataFormatter.shutterSpeed(2.5) == "2.5s")
        #expect(MetadataFormatter.shutterSpeed(0) == nil)
        #expect(MetadataFormatter.shutterSpeed(-1) == nil)
    }

    @Test func apertureFormatting() {
        #expect(MetadataFormatter.aperture(1.8) == "f/1.8")
        #expect(MetadataFormatter.aperture(11) == "f/11")
        #expect(MetadataFormatter.aperture(0) == nil)
    }

    @Test func focalLengthFormatting() {
        #expect(MetadataFormatter.focalLength(85) == "85mm")
        #expect(MetadataFormatter.focalLength(23.5) == "23.5mm")
        #expect(MetadataFormatter.focalLength(0) == nil)
    }

    @Test func isoFormatting() {
        #expect(MetadataFormatter.iso(400) == "ISO 400")
        #expect(MetadataFormatter.iso(0) == nil)
    }

    @Test func megapixelsFormatting() {
        #expect(MetadataFormatter.megapixels(24.2) == "24.2 MP")
        #expect(MetadataFormatter.megapixels(0) == nil)
    }

    @Test func metadataLineSkipsNilValues() {
        #expect(MetadataFormatter.metadataLine(["ISO 400", nil, "85mm", "f/1.8"]) == "ISO 400 · 85mm · f/1.8")
        #expect(MetadataFormatter.metadataLine([nil, nil]) == nil)
    }

    @Test func dateHeaders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let now = date(2026, 7, 19)

        #expect(MetadataFormatter.dayHeader(date(2026, 7, 19), calendar: calendar, now: now, locale: locale) == "Today")
        #expect(MetadataFormatter.dayHeader(date(2026, 7, 18), calendar: calendar, now: now, locale: locale) == "Yesterday")
        #expect(MetadataFormatter.dayHeader(date(2026, 7, 4), calendar: calendar, now: now, locale: locale) == "July 4, 2026")
        #expect(MetadataFormatter.monthHeader(date(2026, 7, 4), calendar: calendar, locale: locale) == "July 2026")
    }
}
