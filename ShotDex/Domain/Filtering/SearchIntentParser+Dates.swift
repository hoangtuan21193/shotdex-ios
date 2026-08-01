import Foundation

extension SearchIntentParser {
    /// Matches every date shape at `index`:
    /// `hôm qua` · `tháng trước` · `năm 2023` · `trước 2020` · `sau 2023`
    /// · `7 ngày qua` · `last 30 days`.
    ///
    /// Every bound is a calendar boundary, computed from the `now` and `calendar`
    /// handed in — the parser never reads the clock, so a test can pin a Tuesday
    /// in March and stay pinned.
    static func dateRule(
        _ tokens: [Token],
        _ index: Int,
        _ now: Date,
        _ calendar: Calendar
    ) -> (SmartAlbumRule, Int)? {
        let token = tokens[index].canonical

        if let named = namedPeriod(token, now: now, calendar: calendar) {
            return (
                SmartAlbumRule(
                    field: .dateTaken,
                    op: .inRange,
                    number: named.start.timeIntervalSince1970,
                    numberUpper: named.end.timeIntervalSince1970
                ),
                1
            )
        }

        // "trước 2020" / "sau 2023". A bare year names a whole year, so "before"
        // means before it started and "after" means after it ended — anything else
        // silently drops twelve months.
        if token == "before" || token == "after",
           index + 1 < tokens.count,
           let year = year(tokens[index + 1].canonical),
           let bounds = yearBounds(year, calendar: calendar) {
            let epoch = token == "before"
                ? bounds.start.timeIntervalSince1970
                : bounds.end.timeIntervalSince1970
            return (
                SmartAlbumRule(
                    field: .dateTaken,
                    op: token == "before" ? .before : .after,
                    number: epoch
                ),
                2
            )
        }

        // "năm 2023" / "year 2023", and a bare four-digit year on its own.
        if token == "year", index + 1 < tokens.count,
           let year = year(tokens[index + 1].canonical),
           let bounds = yearBounds(year, calendar: calendar) {
            return (yearRule(bounds), 2)
        }
        if let year = year(token), let bounds = yearBounds(year, calendar: calendar) {
            return (yearRule(bounds), 1)
        }

        // "7 ngày qua" → [7, daysago]; "last 30 days" → [last, 30, day].
        if let count = Double(token), count > 0, index + 1 < tokens.count {
            switch tokens[index + 1].canonical {
            case "daysago":
                return (SmartAlbumRule(field: .dateTaken, op: .inLastDays, number: count), 2)
            case "monthsago":
                return (
                    SmartAlbumRule(field: .dateTaken, op: .inLastDays, number: count * 30),
                    2
                )
            default:
                break
            }
        }
        if token == "last", index + 2 < tokens.count,
           let count = Double(tokens[index + 1].canonical), count > 0 {
            switch tokens[index + 2].canonical {
            case "day":
                return (SmartAlbumRule(field: .dateTaken, op: .inLastDays, number: count), 3)
            case "month":
                return (
                    SmartAlbumRule(field: .dateTaken, op: .inLastDays, number: count * 30),
                    3
                )
            default:
                break
            }
        }

        return nil
    }

    private static func yearRule(_ bounds: (start: Date, end: Date)) -> SmartAlbumRule {
        SmartAlbumRule(
            field: .dateTaken,
            op: .inRange,
            number: bounds.start.timeIntervalSince1970,
            numberUpper: bounds.end.timeIntervalSince1970
        )
    }

    /// Only plausible capture years, so "iso 2000" is not read as a date. The
    /// lower bound is where photography starts being a thing people have files of.
    static func year(_ token: String) -> Int? {
        guard token.count == 4, let value = Int(token), (1900...2200).contains(value) else {
            return nil
        }
        return value
    }

    private static func yearBounds(_ year: Int, calendar: Calendar) -> (start: Date, end: Date)? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = calendar.date(from: components),
              let next = calendar.date(byAdding: .year, value: 1, to: start)
        else { return nil }
        return (start, next.addingTimeInterval(-1))
    }

    /// Periods that name themselves: today, yesterday, this week, last month…
    static func namedPeriod(
        _ token: String,
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        func range(_ component: Calendar.Component, offset: Int) -> (start: Date, end: Date)? {
            guard let anchor = calendar.date(byAdding: component, value: offset, to: now),
                  let interval = calendar.dateInterval(of: component, for: anchor)
            else { return nil }
            // `end` is the start of the next period; step back so the range is
            // inclusive and cannot pick up the first second of the next day.
            return (interval.start, interval.end.addingTimeInterval(-1))
        }

        switch token {
        case "today": return range(.day, offset: 0)
        case "yesterday": return range(.day, offset: -1)
        case "thisweek": return range(.weekOfYear, offset: 0)
        case "lastweek": return range(.weekOfYear, offset: -1)
        case "thismonth": return range(.month, offset: 0)
        case "lastmonth": return range(.month, offset: -1)
        case "thisyear": return range(.year, offset: 0)
        case "lastyear": return range(.year, offset: -1)
        default: return nil
        }
    }
}
