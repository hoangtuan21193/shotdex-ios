import Foundation
import Testing
@testable import ShotDex

struct StatsDateScopeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func allTimeHasNoInterval() {
        #expect(StatsDateScope.allTime.dateInterval() == nil)
    }

    @Test func thisYearStartsAtJanuaryFirst() throws {
        let now = date(2026, 7, 19)
        let interval = try #require(StatsDateScope.thisYear.dateInterval(now: now, calendar: calendar))
        #expect(interval.lowerBound == Int(date(2026, 1, 1, hour: 0).timeIntervalSince1970))
        #expect(interval.upperBound == Int(now.timeIntervalSince1970))
    }

    @Test func customReturnsItsRangeVerbatim() {
        let range = 1_000...2_000
        #expect(StatsDateScope.custom(range).dateInterval() == range)
    }

    @Test func customFromDaysCoversWholeDays() throws {
        let days = date(2026, 3, 12)...date(2026, 6, 4)
        let scope = StatsDateScope.custom(days: days, calendar: calendar)
        let interval = try #require(scope.dateInterval())
        #expect(interval.lowerBound == Int(date(2026, 3, 12, hour: 0).timeIntervalSince1970))
        // Last second of the end day, so photos taken that evening count.
        #expect(interval.upperBound == Int(date(2026, 6, 5, hour: 0).timeIntervalSince1970) - 1)
    }

    @Test func singleDayRangeIsValid() throws {
        let day = date(2026, 7, 19)
        let scope = StatsDateScope.custom(days: day...day, calendar: calendar)
        let interval = try #require(scope.dateInterval())
        #expect(interval.lowerBound <= interval.upperBound)
        #expect(interval.contains(Int(day.timeIntervalSince1970)))
    }
}
