import Foundation

/// Calendar facts of the capture date that are not a range of dates — the
/// month of any year, the season, the day of the week (FS-01.03c §5). Each is a
/// `.choice` rule field, so search tokens, smart albums and the builder share
/// one definition.
///
/// All three read the capture instant in **the device's time zone at query
/// time** (`'localtime'` in SQLite): `photo_metadata.creationDate` is UTC, and
/// the photo's own zone is not stored. A photo taken late at night in a far
/// zone can land on the neighbouring day — the known price.
enum CaptureCalendarSQL {
    /// Month 1–12 of the capture date, local time.
    static let month = "CAST(strftime('%m', creationDate, 'unixepoch', 'localtime') AS INTEGER)"
    /// Day of week 0 (Sunday) – 6 (Saturday), local time.
    static let weekday = "CAST(strftime('%w', creationDate, 'unixepoch', 'localtime') AS INTEGER)"
    /// The month as the northern hemisphere sees it: south of the equator the
    /// seasons run six months apart, so January there is July here.
    static let seasonMonth = "(CASE WHEN latitude < 0 THEN ((\(month) + 5) % 12) + 1 ELSE \(month) END)"
}

/// A calendar month regardless of year — *June*.
enum CaptureMonthOfYear: Int, CaseIterable, Sendable {
    case january = 1, february, march, april, may, june, july, august, september, october, november, december

    /// Stored in `SmartAlbumRule.text`.
    var value: String { String(rawValue) }

    init?(value: String) {
        guard let number = Int(value), let month = CaptureMonthOfYear(rawValue: number) else { return nil }
        self = month
    }

    var label: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar.standaloneMonthSymbols[rawValue - 1]
    }

    var sql: (String, [Int]) { ("\(CaptureCalendarSQL.month) = ?", [rawValue]) }
}

/// A season, by hemisphere of the capture location (no location: northern).
/// Northern: spring March–May, summer June–August, autumn September–November,
/// winter December–February.
enum CaptureSeason: String, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    var label: String {
        switch self {
        case .spring: String(localized: "Spring", comment: "Season")
        case .summer: String(localized: "Summer", comment: "Season")
        case .autumn: String(localized: "Autumn", comment: "Season")
        case .winter: String(localized: "Winter", comment: "Season")
        }
    }

    /// Months, northern hemisphere.
    var months: [Int] {
        switch self {
        case .spring: [3, 4, 5]
        case .summer: [6, 7, 8]
        case .autumn: [9, 10, 11]
        case .winter: [12, 1, 2]
        }
    }

    var sql: (String, [Int]) { ("\(CaptureCalendarSQL.seasonMonth) IN (?, ?, ?)", months) }
}

/// A day of the week, or the weekend / weekdays.
enum CaptureWeekday: String, CaseIterable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday, weekend, weekday

    /// SQLite `%w` numbers: 0 = Sunday.
    var days: [Int] {
        switch self {
        case .sunday: [0]
        case .monday: [1]
        case .tuesday: [2]
        case .wednesday: [3]
        case .thursday: [4]
        case .friday: [5]
        case .saturday: [6]
        case .weekend: [0, 6]
        case .weekday: [1, 2, 3, 4, 5]
        }
    }

    var label: String {
        switch self {
        case .weekend: return String(localized: "Weekend", comment: "Day of week condition: Saturday or Sunday")
        case .weekday: return String(localized: "Weekday", comment: "Day of week condition: Monday to Friday")
        default:
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = .current
            return calendar.standaloneWeekdaySymbols[days[0]]
        }
    }

    var sql: (String, [Int]) {
        let marks = Array(repeating: "?", count: days.count).joined(separator: ", ")
        return ("\(CaptureCalendarSQL.weekday) IN (\(marks))", days)
    }
}
