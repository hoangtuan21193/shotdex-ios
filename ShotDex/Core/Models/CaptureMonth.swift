import Foundation

/// A calendar month of the capture date — the "in month" condition of the
/// Library filter and of smart albums (FS-01.05 §4, FS-06.08 §2), and what
/// Insights' busiest-month sentence opens. Always the device's local calendar
/// and time zone, like every other grouping by time (FS-07.01 §5).
struct CaptureMonth: Codable, Hashable, Sendable {
    var year: Int
    /// 1…12.
    var month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month `date` falls in, in `calendar`.
    init(containing date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1)
    }

    /// The instant a smart-album rule stores for the month: the 15th at noon.
    /// Halfway through, so the rule still names the same month after the
    /// device moves up to 14 hours of time zone either way.
    func anchorDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 15, hour: 12)) ?? .distantPast
    }

    /// Start of the month up to, not including, the start of the next —
    /// half-open, so a photo at 23:30 on the last day is in and one at 00:00
    /// on the first of the next month is out.
    func interval(calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: anchorDate(calendar: calendar))
            ?? DateInterval(start: anchorDate(calendar: calendar), duration: 0)
    }

    /// The SQL condition on `creationDate` (epoch seconds) and its bounds.
    func creationDateCondition(calendar: Calendar = .current) -> (sql: String, arguments: [Int]) {
        let interval = interval(calendar: calendar)
        return ("creationDate >= ? AND creationDate < ?",
                [Int(interval.start.timeIntervalSince1970), Int(interval.end.timeIntervalSince1970)])
    }

    /// "Aug 2026" — the chip and the condition summary.
    func abbreviatedName(locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated).year()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return anchorDate(calendar: calendar).formatted(style)
    }
}
