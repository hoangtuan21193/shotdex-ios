import Foundation
import Testing
@testable import ShotDex

struct OnThisDayNotificationScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func tally(_ date: Date, count: Int, bytes: Int = 0, sized: Int = 0) -> OnThisDayDayTally {
        OnThisDayDayTally(
            date: date, photoCount: count, indexedByteCount: bytes, sizedPhotoCount: sized
        )
    }

    // MARK: Target days

    @Test func targetDaysCoverTheHorizonStartingToday() {
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 6)
        )
        #expect(days.count == OnThisDayNotificationSchedule.horizonDays)
        #expect(days.first == date(2026, 7, 28, hour: 0))
        #expect(days.last == date(2026, 8, 3, hour: 0))
        // Day-aligned and ascending.
        #expect(days == days.sorted())
        #expect(days.allSatisfy { calendar.startOfDay(for: $0) == $0 })
    }

    @Test func todayDropsOutOnceItsNotifyTimeHasPassed() {
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 10)
        )
        #expect(days.count == OnThisDayNotificationSchedule.horizonDays - 1)
        #expect(days.first == date(2026, 7, 29, hour: 0))
    }

    @Test func todayDropsOutAtTheExactNotifyTime() {
        // A calendar trigger whose date is not strictly in the future is never
        // delivered, so equality has to count as "already passed".
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 9, minute: 0)
        )
        #expect(days.first == date(2026, 7, 29, hour: 0))
    }

    @Test func notifyTimeInsideTheDaylightSavingGapSkipsThatDay() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-03-08 jumps 02:00 → 03:00, so 02:30 does not exist that day.
        let now = pacific.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 1))!
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 2 * 60 + 30, calendar: pacific, now: now
        )
        let skipped = pacific.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        #expect(!days.contains(skipped))
        #expect(days.count == OnThisDayNotificationSchedule.horizonDays - 1)
    }

    // MARK: Requests

    @Test func daysWithNoPhotosProduceNoRequest() {
        let requests = OnThisDayNotificationSchedule.requests(
            from: [
                tally(date(2026, 7, 29, hour: 0), count: 0),
                tally(date(2026, 7, 30, hour: 0), count: 4),
            ],
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 10),
            body: { "\($0.photoCount)" }
        )
        #expect(requests.count == 1)
        #expect(requests[0].dayKey == "2026-07-30")
        #expect(requests[0].body == "4")
    }

    @Test func identifiersAreDayKeyedAndUnique() {
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: 9 * 60, calendar: calendar, now: date(2026, 7, 28, hour: 6)
        )
        let requests = OnThisDayNotificationSchedule.requests(
            from: days.map { tally($0, count: 1) },
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 6),
            body: { _ in "body" }
        )
        #expect(requests.count == OnThisDayNotificationSchedule.horizonDays)
        #expect(requests[0].identifier == "onThisDay.2026-07-28")
        #expect(Set(requests.map(\.identifier)).count == requests.count)
        #expect(requests.allSatisfy {
            $0.identifier.hasPrefix(OnThisDayNotificationSchedule.identifierPrefix)
        })
    }

    @Test func fireComponentsCarryTheDayAndTimeAndNoTimeZone() {
        let requests = OnThisDayNotificationSchedule.requests(
            from: [tally(date(2026, 7, 30, hour: 0), count: 2)],
            notifyMinutes: 20 * 60 + 45,
            calendar: calendar,
            now: date(2026, 7, 28, hour: 6),
            body: { _ in "body" }
        )
        let components = requests[0].fireComponents
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 30)
        #expect(components.hour == 20)
        #expect(components.minute == 45)
        // Left unset on purpose: fire at the chosen wall-clock time wherever the
        // user is, not at the zone the reminder was scheduled in.
        #expect(components.timeZone == nil)
    }

    @Test func feb29IsScheduledAsATargetDayInALeapYear() {
        let requests = OnThisDayNotificationSchedule.requests(
            from: [tally(date(2028, 2, 29, hour: 0), count: 3)],
            notifyMinutes: 9 * 60,
            calendar: calendar,
            now: date(2028, 2, 28, hour: 6),
            body: { _ in "body" }
        )
        #expect(requests.count == 1)
        #expect(requests[0].dayKey == "2028-02-29")
    }

    // MARK: Day keys and time conversion

    @Test func dayKeyRoundTripsAcrossTimeZones() {
        let key = OnThisDayNotificationSchedule.dayKey(
            for: date(2026, 7, 29, hour: 0), calendar: calendar
        )
        #expect(key == "2026-07-29")

        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parsed = OnThisDayNotificationSchedule.date(fromDayKey: key, calendar: pacific)
        let components = pacific.dateComponents([.year, .month, .day], from: parsed!)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 29)
    }

    @Test func malformedDayKeyReturnsNil() {
        #expect(OnThisDayNotificationSchedule.date(fromDayKey: "nope", calendar: calendar) == nil)
    }

    @Test func minutesSinceMidnightRoundTrips() {
        for minutes in [0, 540, 1_439] {
            let day = date(2026, 7, 28, hour: 0)
            let converted = OnThisDayNotificationSchedule.date(
                fromMinutesSinceMidnight: minutes, on: day, calendar: calendar
            )!
            #expect(
                OnThisDayNotificationSchedule.minutesSinceMidnight(
                    from: converted, calendar: calendar
                ) == minutes
            )
        }
    }
}
