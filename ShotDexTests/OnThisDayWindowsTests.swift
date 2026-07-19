import Foundation
import Testing
@testable import ShotDex

struct OnThisDayWindowsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func regularDateProducesOneWindowPerPreviousYear() {
        let windows = OnThisDayWindows.windows(
            for: date(2026, 7, 19),
            earliestYear: 2023,
            calendar: calendar,
            now: date(2026, 7, 19)
        )
        #expect(windows.count == 3)
        // Newest first, each window is exactly one day starting at midnight.
        #expect(windows[0].start == date(2025, 7, 19, hour: 0))
        #expect(windows[0].end == date(2025, 7, 20, hour: 0))
        #expect(windows[1].start == date(2024, 7, 19, hour: 0))
        #expect(windows[2].start == date(2023, 7, 19, hour: 0))
    }

    @Test func currentYearIsExcluded() {
        let windows = OnThisDayWindows.windows(
            for: date(2026, 7, 19),
            earliestYear: 2026,
            calendar: calendar,
            now: date(2026, 7, 19)
        )
        #expect(windows.isEmpty)
    }

    @Test func earliestYearAfterCurrentYearIsEmpty() {
        let windows = OnThisDayWindows.windows(
            for: date(2026, 7, 19),
            earliestYear: 2030,
            calendar: calendar,
            now: date(2026, 7, 19)
        )
        #expect(windows.isEmpty)
    }

    @Test func feb29SkipsNonLeapYears() {
        let windows = OnThisDayWindows.windows(
            for: date(2024, 2, 29),
            earliestYear: 2019,
            calendar: calendar,
            now: date(2026, 1, 1)
        )
        // 2025, 2023, 2022, 2021, 2019 have no Feb 29 — only 2024 and 2020 remain.
        #expect(windows.count == 2)
        #expect(windows[0].start == date(2024, 2, 29, hour: 0))
        #expect(windows[1].start == date(2020, 2, 29, hour: 0))
    }

    @Test func selectedDateYearDoesNotMatter() {
        // Picking a date in 2019 still matches that month/day across all years.
        let windows = OnThisDayWindows.windows(
            for: date(2019, 3, 5),
            earliestYear: 2024,
            calendar: calendar,
            now: date(2026, 7, 19)
        )
        #expect(windows.count == 2)
        #expect(windows[0].start == date(2025, 3, 5, hour: 0))
        #expect(windows[1].start == date(2024, 3, 5, hour: 0))
    }

    @Test func cappedAt100YearsBack() {
        let windows = OnThisDayWindows.windows(
            for: date(2026, 7, 19),
            earliestYear: 1800,
            calendar: calendar,
            now: date(2026, 7, 19)
        )
        #expect(windows.count == OnThisDayWindows.maxYearsBack)
        #expect(windows.last!.start == date(1926, 7, 19, hour: 0))
    }
}
