import SwiftUI
import WidgetKit

/// The Lock Screen face of a photo widget.
///
/// Separate from `PhotoWidgetFace` on purpose. That view's whole job is to lay
/// a chosen typeface, colour and position over a photo, and the Lock Screen
/// offers none of those: it renders an accessory widget in a single tinted
/// colour, in a strip the width of a sentence, with no background of its own.
/// So what survives the trip is the data — a temperature, a condition, the
/// next thing on today — and these views show that and nothing else.
struct PhotoWidgetAccessoryView: View {
    let entry: PhotoWidgetEntry
    let family: WidgetFamily

    /// The design decides, in the order of what is worth a Lock Screen strip:
    /// the weather, then what is on today, then the date. **Never the time** —
    /// the Lock Screen already has a clock, and a second one is the reason the
    /// old Clock widget was not offered here at all.
    var body: some View {
        if entry.settings.showsWeather {
            WeatherAccessoryView(
                weather: entry.weather,
                settings: entry.settings,
                date: entry.date,
                family: family
            )
        } else if entry.settings.showsCalendar {
            CalendarAccessoryView(
                snapshot: entry.calendarSnapshot,
                date: entry.date,
                family: family
            )
        } else {
            DateAccessoryView(date: entry.date, settings: entry.settings, family: family)
        }
    }
}

// MARK: - Weather

struct WeatherAccessoryView: View {
    let weather: WeatherSnapshot?
    let settings: PhotoWidgetSettings
    let date: Date
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline takes one image and one line of text, and the system
            // draws both; nothing else is honoured there.
            Label {
                Text(inlineText)
            } icon: {
                Image(systemName: symbolName)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: symbolName)
                        .font(.title3)
                    Text(temperature)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: symbolName)
                Text(temperature)
                    .font(.headline)
                    .monospacedDigit()
                Text(condition)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let detail = detailLine {
                Text(detail)
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Copy

    /// A reading is shown as unavailable rather than as a wrong number: the
    /// Lock Screen has no room to explain, so it says nothing it cannot back.
    private var isUsable: Bool {
        guard let weather else { return false }
        return !weather.isStale(at: date)
    }

    private var symbolName: String {
        guard let weather, isUsable else { return "thermometer.medium.slash" }
        return WeatherFormat.symbolName(code: weather.conditionCode, isNight: weather.isNight)
    }

    private var temperature: String {
        guard let weather, isUsable else { return "--°" }
        return WeatherFormat.temperatureString(
            celsius: weather.temperatureCelsius, unit: settings.temperatureUnit
        )
    }

    private var condition: String {
        guard let weather, isUsable else { return "Open ShotDex" }
        return WeatherFormat.conditionName(code: weather.conditionCode)
    }

    private var inlineText: String {
        guard isUsable else { return "Weather — open ShotDex" }
        return "\(temperature) \(condition)"
    }

    /// High and low, then the place — whichever the user left on, and only one
    /// of them: the strip is two lines tall.
    private var detailLine: String? {
        guard let weather, isUsable else { return nil }
        if settings.showsHighLow,
           let highLow = WeatherFormat.highLowString(
               highCelsius: weather.highCelsius,
               lowCelsius: weather.lowCelsius,
               unit: settings.temperatureUnit
           ) {
            if settings.showsWeatherPlace, let place = weather.placeName {
                return "\(highLow)  ·  \(place)"
            }
            return highLow
        }
        return settings.showsWeatherPlace ? weather.placeName : nil
    }
}

// MARK: - Calendar

struct CalendarAccessoryView: View {
    let snapshot: CalendarSnapshot?
    let date: Date
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text(inlineText)
            } icon: {
                Image(systemName: "calendar")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(monthText)
                        .font(.caption2)
                        .textCase(.uppercase)
                    Text(dayText)
                        .font(.title2.weight(.medium))
                        .monospacedDigit()
                }
            }
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(weekdayAndDate)
                .font(.headline)
                .lineLimit(1)
            if let event = nextEvent {
                Text("\(CalendarFormat.timeString(for: event))  \(event.title)")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text(emptyLine)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let remaining = remainingLine {
                Text(remaining)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Copy

    /// Today's events, or nil when the file is for another day — a Lock Screen
    /// left untouched overnight must not offer yesterday's meetings.
    private var todaysEvents: [CalendarSnapshot.Event]? {
        guard let snapshot, snapshot.hasAccess else { return nil }
        return snapshot.events(on: date)
    }

    private var nextEvent: CalendarSnapshot.Event? {
        guard let events = todaysEvents else { return nil }
        return CalendarFormat.nextEvent(in: events, at: date)
    }

    private var emptyLine: String {
        guard let snapshot else { return "Open ShotDex" }
        if !snapshot.hasAccess { return "Calendar access is off" }
        if snapshot.events(on: date) == nil { return "Open ShotDex for today" }
        return "Nothing left today"
    }

    /// How many more are on after the one being shown.
    private var remainingLine: String? {
        guard let events = todaysEvents, let next = nextEvent else { return nil }
        let later = events.filter { $0.id != next.id }.count
        guard later > 0 else { return nil }
        return later == 1 ? "1 more today" : "\(later) more today"
    }

    private var inlineText: String {
        if let event = nextEvent {
            return "\(CalendarFormat.timeString(for: event)) \(event.title)"
        }
        return emptyLine
    }

    private var weekdayAndDate: String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var monthText: String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    private var dayText: String {
        date.formatted(.dateTime.day())
    }
}

// MARK: - Date

/// What a design with neither the weather nor the calendar has left worth
/// putting on a Lock Screen: the day. Drawn in the design's own date format,
/// so the strip reads the way the Home Screen widget does.
struct DateAccessoryView: View {
    let date: Date
    let settings: PhotoWidgetSettings
    let family: WidgetFamily

    private var text: String {
        PhotoWidgetFormat.dateString(for: date, settings: settings)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text(text)
            } icon: {
                Image(systemName: "photo")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(date, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .textCase(.uppercase)
                    Text(date, format: .dateTime.day())
                        .font(.title2.weight(.medium))
                        .monospacedDigit()
                }
            }
        default:
            Text(text)
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
