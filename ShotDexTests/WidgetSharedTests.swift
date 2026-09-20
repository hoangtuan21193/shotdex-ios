import Foundation
import Testing
@testable import ShotDex

/// The pure parts of the widget payloads: the day key both processes spell,
/// the deep links a tap carries, which photos a day features, how a clock
/// format is sanitized and which album frame is showing.
struct WidgetSharedTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Day keys

    @Test func dayKeyPadsToFixedWidth() {
        #expect(WidgetSharedContainer.dayKey(for: date(2026, 9, 5), calendar: calendar) == "2026-09-05")
        #expect(WidgetSharedContainer.dayKey(for: date(2026, 12, 31), calendar: calendar) == "2026-12-31")
    }

    @Test func dayKeyRoundTripsToLocalMidnight() throws {
        let key = WidgetSharedContainer.dayKey(for: date(2026, 9, 20, hour: 23), calendar: calendar)
        let parsed = try #require(WidgetSharedContainer.date(fromDayKey: key, calendar: calendar))
        #expect(parsed == date(2026, 9, 20, hour: 0))
    }

    @Test func malformedDayKeysAreRejected() {
        for key in ["", "2026-9-5", "2026-13-01", "2026-02-30", "not-a-day", "2026-09-05-01"] {
            #expect(WidgetSharedContainer.date(fromDayKey: key, calendar: calendar) == nil)
        }
    }

    // MARK: Deep links

    @Test func onThisDayLinkRoundTrips() {
        let link = WidgetDeepLink.onThisDay(dayKey: "2026-09-20")
        #expect(WidgetDeepLink(url: link.url) == link)
    }

    /// A PhotoKit local identifier contains slashes, which is why it travels
    /// as a query item rather than a path component.
    @Test func photoLinkSurvivesAnIdentifierWithSlashes() {
        let link = WidgetDeepLink.photo(assetId: "9F3C1B2A-1111-2222-3333-444455556666/L0/001")
        #expect(WidgetDeepLink(url: link.url) == link)
    }

    @Test func foreignAndIncompleteURLsAreNotLinks() {
        for string in [
            "https://example.com/on-this-day?day=2026-09-20",
            "shotdex://on-this-day",
            "shotdex://photo?id=",
            "shotdex://statistics",
        ] {
            #expect(WidgetDeepLink(url: URL(string: string)!) == nil)
        }
    }

    // MARK: On This Day selection

    @Test func featuredPhotosTakeOneYearEachBeforeDoublingUp() {
        // Four photos from 2025, then one each from 2024 and 2022.
        let years = [2025, 2025, 2025, 2025, 2024, 2022]
        #expect(OnThisDaySnapshot.featuredIndices(years: years) == [0, 4, 5, 1])
    }

    @Test func featuredPhotosFallBackToOrderWhenOneYearIsAll() {
        #expect(OnThisDaySnapshot.featuredIndices(years: [2024, 2024, 2024]) == [0, 1, 2])
        #expect(OnThisDaySnapshot.featuredIndices(years: []) == [])
    }

    @Test func writerCoversTodayAndTheDaysTheWidgetRollsOverTo() {
        let days = OnThisDaySnapshotWriter.days(from: date(2026, 9, 20, hour: 22), calendar: calendar)
        #expect(days.count == OnThisDaySnapshot.daysAhead + 1)
        #expect(days.first == date(2026, 9, 20, hour: 0))
        #expect(days.last == date(2026, 9, 20 + OnThisDaySnapshot.daysAhead, hour: 0))
    }

    // MARK: Clock formats

    /// A widget is rebuilt once a minute at best, so a seconds field would sit
    /// frozen on a wrong value — it is removed when the format is stored.
    @Test func secondsAreStrippedFromAClockFormat() {
        #expect(ClockWidgetFormat.sanitized(pattern: "HH:mm:ss") == "HH:mm:")
        #expect(ClockWidgetFormat.sanitized(pattern: "  h:mm a  ") == "h:mm a")
        #expect(ClockWidgetFormat.sanitized(pattern: "") == "")
    }

    @Test func customPatternsAreUsedAndEmptyOnesFollowTheRegion() {
        var settings = ClockWidgetSettings.default
        settings.timeFormat = "HH:mm"
        settings.dateFormat = "yyyy-MM-dd"
        let moment = date(2026, 9, 20, hour: 9)
        let zone = calendar.timeZone
        #expect(
            ClockWidgetFormat.timeString(
                for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
            ) == "09:00"
        )
        #expect(
            ClockWidgetFormat.dateString(
                for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
            ) == "2026-09-20"
        )

        settings.timeFormat = ""
        let systemTime = ClockWidgetFormat.timeString(
            for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
        )
        // en_GB is a 24-hour region, so the short style has no AM/PM marker.
        #expect(systemTime.contains("09"))
    }

    // MARK: Clock rotation

    @Test func albumRotationPicksOneFramePerHourOrDay() {
        let noon = date(2026, 9, 20, hour: 12)
        let laterHour = date(2026, 9, 20, hour: 13)
        let nextDay = date(2026, 9, 21, hour: 12)

        let hourly = ClockWidgetSnapshot.frameIndex(
            at: noon, count: 4, rotation: .hourly, calendar: calendar
        )
        let hourlyLater = ClockWidgetSnapshot.frameIndex(
            at: laterHour, count: 4, rotation: .hourly, calendar: calendar
        )
        #expect(hourly != hourlyLater)

        let daily = ClockWidgetSnapshot.frameIndex(
            at: noon, count: 4, rotation: .daily, calendar: calendar
        )
        #expect(
            ClockWidgetSnapshot.frameIndex(
                at: laterHour, count: 4, rotation: .daily, calendar: calendar
            ) == daily
        )
        #expect(
            ClockWidgetSnapshot.frameIndex(
                at: nextDay, count: 4, rotation: .daily, calendar: calendar
            ) != daily
        )

        #expect(
            ClockWidgetSnapshot.frameIndex(
                at: laterHour, count: 4, rotation: .never, calendar: calendar
            ) == 0
        )
    }

    @Test func rotationHasNoFrameWhenThereAreNoPictures() {
        for rotation in ClockWidgetSettings.Rotation.allCases {
            #expect(
                ClockWidgetSnapshot.frameIndex(
                    at: .now, count: 0, rotation: rotation, calendar: calendar
                ) == nil
            )
        }
    }

    // MARK: Colour

    @Test func hexColoursParseWithOrWithoutTheHash() throws {
        let withHash = try #require(WidgetTextColor.components(hex: "#EB9526"))
        let without = try #require(WidgetTextColor.components(hex: "eb9526"))
        #expect(withHash.red == without.red)
        #expect(abs(withHash.red - 235.0 / 255) < 0.001)
        #expect(abs(withHash.green - 149.0 / 255) < 0.001)
        #expect(abs(withHash.blue - 38.0 / 255) < 0.001)
    }

    @Test func nonsenseHexIsNotAColour() {
        for hex in ["", "#FFF", "#GGGGGG", "FFFFFFFF"] {
            #expect(WidgetTextColor.components(hex: hex) == nil)
            #expect(!WidgetTextColor.isValid(hex: hex))
        }
        #expect(WidgetTextColor.swatches.allSatisfy { WidgetTextColor.isValid(hex: $0) })
    }

    // MARK: Scaling

    @Test func theMediumWidgetGetsExactlyTheSizeTheUserSet() {
        var settings = ClockWidgetSettings.default
        settings.timeSize = 40
        #expect(settings.scaledTimeSize(forWidgetWidth: 329) == 40)
        #expect(settings.scaledTimeSize(forWidgetWidth: 158) < 40)
        #expect(settings.scaledTimeSize(forWidgetWidth: 360) > 40)
        // A clock is never scaled into illegibility, however narrow the family.
        #expect(settings.scaledTimeSize(forWidgetWidth: 10) >= 40 * 0.6)
    }
}
