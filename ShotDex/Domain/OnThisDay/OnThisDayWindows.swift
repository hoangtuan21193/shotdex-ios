import Foundation

/// Builds the per-year date windows for the "On This Day" smart album:
/// for the month/day of a reference date, one `[startOfDay, +1 day)` interval
/// per year strictly before the current year, newest first.
enum OnThisDayWindows {
    /// Safety cap: never look further back than this many years.
    static let maxYearsBack = 100

    /// - Parameters:
    ///   - date: the reference date whose month/day is matched.
    ///   - earliestYear: year of the oldest asset in the library; windows
    ///     before it would never match anything.
    ///   - calendar: injected for testability (timezone-sensitive).
    ///   - now: "today", injected for testability. Years >= the current year
    ///     are excluded — the album shows previous years only.
    static func windows(
        for date: Date,
        earliestYear: Int,
        calendar: Calendar,
        now: Date
    ) -> [DateInterval] {
        let currentYear = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        let lowerBound = max(earliestYear, currentYear - maxYearsBack)
        guard lowerBound < currentYear else { return [] }

        var result: [DateInterval] = []
        for year in stride(from: currentYear - 1, through: lowerBound, by: -1) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            // Feb 29 does not exist in non-leap years; skip instead of
            // letting the calendar roll over to Mar 1.
            guard let start = calendar.date(from: components),
                  calendar.component(.day, from: start) == day,
                  calendar.component(.month, from: start) == month,
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { continue }
            result.append(DateInterval(start: start, end: end))
        }
        return result
    }
}
