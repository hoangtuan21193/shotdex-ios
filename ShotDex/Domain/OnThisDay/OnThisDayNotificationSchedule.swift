import Foundation

/// One scheduled "On This Day" reminder, ready to be handed to the system.
struct OnThisDayNotificationRequest: Equatable, Sendable {
    let identifier: String
    /// `yyyy-MM-dd` of the day this reminder is about; travels in the
    /// notification's `userInfo` so a tap can open that exact day.
    let dayKey: String
    /// Year/month/day/hour/minute, deliberately with no `timeZone`: the
    /// reminder should fire at the chosen wall-clock time wherever the user is
    /// when it fires, not at the zone it was scheduled in.
    let fireComponents: DateComponents
    let title: String
    let body: String
}

/// Decides which days get a reminder, what identifier each one carries, and
/// when it fires. Pure — a local notification cannot run code at delivery
/// time, so the whole week is decided up front and re-decided on every refresh.
enum OnThisDayNotificationSchedule {
    /// How many days ahead are scheduled at once. Reminders pause if the app is
    /// not opened (and no background refresh runs) for longer than this.
    static let horizonDays = 7
    /// 09:00, as minutes since local midnight.
    static let defaultNotifyMinutes = 9 * 60
    /// Every request this feature owns starts with this. Removals are scoped to
    /// it so a future notification feature is never collateral damage.
    static let identifierPrefix = "onThisDay."
    /// `userInfo` key carrying `dayKey`.
    static let dayKeyUserInfoKey = "onThisDayDayKey"
    static let categoryIdentifier = "onThisDay"

    /// The days worth measuring: today through today + `horizon` - 1, minus any
    /// whose fire time is not in the future.
    ///
    /// Today drops out once its notify time has passed (a calendar trigger in
    /// the past is simply never delivered), and a day drops out when the notify
    /// time does not exist on it — the hour skipped by a DST spring-forward
    /// would otherwise produce a trigger that silently never fires.
    static func targetDays(
        notifyMinutes: Int,
        calendar: Calendar,
        now: Date,
        horizon: Int = horizonDays
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<horizon).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = fireDate(on: day, notifyMinutes: notifyMinutes, calendar: calendar),
                  fireDate > now
            else { return nil }
            return day
        }
    }

    /// Turns tallies into requests, dropping days with nothing to show and days
    /// whose fire time is no longer ahead. Input order is preserved.
    static func requests(
        from tallies: [OnThisDayDayTally],
        notifyMinutes: Int,
        calendar: Calendar,
        now: Date,
        body: (OnThisDayDayTally) -> String
    ) -> [OnThisDayNotificationRequest] {
        tallies.compactMap { tally in
            guard tally.photoCount > 0,
                  let fireDate = fireDate(on: tally.date, notifyMinutes: notifyMinutes, calendar: calendar),
                  fireDate > now
            else { return nil }

            var components = calendar.dateComponents([.year, .month, .day], from: tally.date)
            components.hour = notifyMinutes / 60
            components.minute = notifyMinutes % 60

            let key = dayKey(for: tally.date, calendar: calendar)
            return OnThisDayNotificationRequest(
                identifier: identifier(forDayKey: key),
                dayKey: key,
                fireComponents: components,
                title: OnThisDayNotificationCopy.title,
                body: body(tally)
            )
        }
    }

    /// The wall-clock moment `notifyMinutes` names on `day`, or nil when that
    /// time does not exist there (DST spring-forward gap).
    static func fireDate(on day: Date, notifyMinutes: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let hour = notifyMinutes / 60
        let minute = notifyMinutes % 60
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components),
              calendar.component(.hour, from: date) == hour,
              calendar.component(.minute, from: date) == minute
        else { return nil }
        return date
    }

    /// Fixed `yyyy-MM-dd`, built from components rather than a `DateFormatter`
    /// so it is neither locale- nor calendar-format-sensitive. Only the
    /// month/day are used downstream, so the key survives a timezone change
    /// between scheduling and tapping.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Keyed by day, not by time, so changing the reminder time replaces the
    /// pending set instead of piling a second request onto the same day.
    static func identifier(forDayKey key: String) -> String {
        identifierPrefix + key
    }

    static func minutesSinceMidnight(from date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(
        fromMinutesSinceMidnight minutes: Int,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return calendar.date(from: components)
    }
}
