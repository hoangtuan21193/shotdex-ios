import Foundation

/// Today's events, as the app read them out of the user's calendars.
///
/// Same rule as the weather: the widget reads a file. EventKit access is
/// granted to the app, the events are read when the app is open, and the
/// widget is handed titles and times — never a store handle, never a calendar
/// identifier it could ask for more with.
struct CalendarSnapshot: Codable, Equatable {
    struct Event: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var startDate: Date
        var endDate: Date
        var isAllDay: Bool
        /// The calendar's own colour, `#RRGGBB`, so the dot beside an event
        /// matches the app the user set it in.
        var colorHex: String?
    }

    /// `WidgetSharedContainer.dayKey` of the day these events are on.
    var dayKey: String
    var events: [Event]
    /// False when the user has not granted calendar access, so the widget can
    /// say so rather than showing an empty day.
    var hasAccess: Bool
    var generatedAt: Date

    static let fileName = "calendar.json"
    /// More than any widget lists; the extra ones are the "+N more" count.
    static let maxEvents = 8

    static func read() -> CalendarSnapshot? {
        guard let url = WidgetSharedContainer.url?.appendingPathComponent(fileName)
        else { return nil }
        return WidgetSharedContainer.decode(CalendarSnapshot.self, at: url)
    }

    /// The events for `date`, or nil when the file is for another day — a
    /// widget that was not refreshed overnight must not show yesterday's
    /// meetings as today's.
    func events(on date: Date, calendar: Calendar = .current) -> [Event]? {
        guard dayKey == WidgetSharedContainer.dayKey(for: date, calendar: calendar)
        else { return nil }
        return events
    }
}

/// The month grid the calendar widget draws: which day sits in which column,
/// with the leading blanks. Pure arithmetic, so the awkward cases (a month
/// starting on a Sunday, a week that starts on Monday, February) are unit
/// tests rather than a screenshot taken in one month of the year.
enum MonthGrid {
    struct Layout: Equatable {
        /// Localised one-letter weekday headers, in display order.
        var weekdaySymbols: [String]
        /// Day numbers in display order, with nil for the leading and
        /// trailing blanks that keep the columns square.
        var days: [Int?]
        /// Index into `days` of the day the grid is built for.
        var todayIndex: Int?
        var monthName: String
    }

    /// The grid for the month `date` falls in. The week starts on the day the
    /// region starts it on — assigning the locale to the calendar is what sets
    /// that — unless the user asked for Monday, which overrides it.
    static func layout(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        weekStartsOnMonday: Bool = false
    ) -> Layout {
        var calendar = calendar
        calendar.locale = locale
        if weekStartsOnMonday { calendar.firstWeekday = 2 }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let firstOfMonth = calendar.date(
            from: DateComponents(year: components.year, month: components.month, day: 1)
        ),
            let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else {
            return Layout(weekdaySymbols: [], days: [], todayIndex: nil, monthName: "")
        }

        // How many blanks before the 1st: the distance from the week's first
        // day to the weekday the month starts on.
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Int?] = Array(repeating: nil, count: leading)
        days.append(contentsOf: dayRange.map { Optional($0) })
        // Pad to whole weeks so the last row does not collapse.
        while days.count % 7 != 0 { days.append(nil) }

        let today = components.day
        let todayIndex = today.map { leading + $0 - 1 }

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let rotated = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])

        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.calendar = calendar
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        return Layout(
            weekdaySymbols: rotated,
            days: days,
            todayIndex: todayIndex,
            monthName: monthFormatter.string(from: date)
        )
    }
}

/// How an event's time reads on a widget: `09:30`, or `All day`.
enum CalendarFormat {
    static func timeString(
        for event: CalendarSnapshot.Event,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: event.startDate)
    }

    /// How many events a family has room for. A small widget only gives up
    /// rows when it is also drawing the month grid; on its own the list has
    /// the whole widget, and cutting it short left blank space above a
    /// "+2 more". Pure, so the rule is a test rather than a screenshot.
    static func eventLimit(isCompact: Bool, showsGrid: Bool, maximum: Int) -> Int {
        guard isCompact, showsGrid else { return maximum }
        return min(maximum, 2)
    }

    /// The one event a Lock Screen strip has room for: the next one still to
    /// start, or the one running now, and an all-day entry only when nothing
    /// timed is left. Pure, so "what does the widget say at 09:31" is a test.
    static func nextEvent(
        in events: [CalendarSnapshot.Event],
        at date: Date
    ) -> CalendarSnapshot.Event? {
        let timed = events.filter { !$0.isAllDay }
        if let upcoming = timed
            .filter({ $0.endDate > date })
            .min(by: { $0.startDate < $1.startDate }) {
            return upcoming
        }
        return events.first { $0.isAllDay }
    }

    /// The events a widget lists, and how many were left over.
    static func visibleEvents(
        _ events: [CalendarSnapshot.Event],
        limit: Int
    ) -> (shown: [CalendarSnapshot.Event], remaining: Int) {
        guard limit > 0 else { return ([], events.count) }
        let shown = Array(events.prefix(limit))
        return (shown, max(0, events.count - shown.count))
    }
}
