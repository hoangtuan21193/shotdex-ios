import SwiftUI

/// Everything a photo widget draws over its picture: the time, the date, a
/// month grid or today's events, and the weather — whichever of them the
/// user's settings turn on.
///
/// One view for all four widgets **and** for the live preview in Settings, so
/// what the user sets up is drawn by the code that draws the widget. A second
/// implementation for the preview is how a preview starts lying.
struct PhotoWidgetFace: View {
    let date: Date
    let settings: PhotoWidgetSettings
    let kind: PhotoWidgetKind
    /// Widget width in points; every size scales from it.
    let width: Double
    var weather: WeatherSnapshot?
    var calendarSnapshot: CalendarSnapshot?
    /// Tall families get the grid and the event list; a small one has room for
    /// one of them.
    var isCompact = false

    private var headlineSize: CGFloat { settings.scaledHeadlineSize(forWidgetWidth: width) }
    private var supportingSize: CGFloat { settings.scaledSupportingSize(forWidgetWidth: width) }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 4) {
            if settings.showsTime {
                Text(PhotoWidgetFormat.timeString(for: date, settings: settings))
                    .font(font(size: headlineSize, isBold: settings.isBold))
            }
            if settings.showsDate {
                Text(PhotoWidgetFormat.dateString(for: date, settings: settings))
                    .font(font(size: supportingSize, isBold: false))
            }
            if kind.needsWeather {
                weatherRow
            }
            if kind.needsCalendarEvents {
                calendarRows
            }
            if isEmpty {
                // A widget with every row off would be an empty rectangle the
                // user cannot tell from a broken one.
                Text("ShotDex")
                    .font(font(size: supportingSize, isBold: false))
            }
        }
        .foregroundStyle(WidgetTextColor.color(hex: settings.textColorHex))
        .shadow(
            color: .black.opacity(settings.legibility == .shadow ? 0.55 : 0),
            radius: 4,
            y: 1
        )
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(textAlignment)
    }

    private var isEmpty: Bool {
        !settings.showsTime && !settings.showsDate
            && !kind.needsWeather && !kind.needsCalendarEvents
    }

    // MARK: Weather

    @ViewBuilder
    private var weatherRow: some View {
        if let weather, !weather.isStale(at: date) {
            VStack(alignment: horizontalAlignment, spacing: 1) {
                HStack(spacing: 6) {
                    Image(
                        systemName: WeatherFormat.symbolName(
                            code: weather.conditionCode, isNight: weather.isNight
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    Text(
                        WeatherFormat.temperatureString(
                            celsius: weather.temperatureCelsius,
                            unit: settings.temperatureUnit
                        )
                    )
                    .font(font(size: weatherTemperatureSize, isBold: settings.isBold))
                    Text(WeatherFormat.conditionName(code: weather.conditionCode))
                        .font(font(size: supportingSize, isBold: false))
                        .lineLimit(1)
                }
                if settings.showsHighLow,
                   let highLow = WeatherFormat.highLowString(
                       highCelsius: weather.highCelsius,
                       lowCelsius: weather.lowCelsius,
                       unit: settings.temperatureUnit
                   ) {
                    Text(highLow)
                        .font(font(size: supportingSize * 0.9, isBold: false))
                        .monospacedDigit()
                }
                if settings.showsWeatherPlace, let place = weather.placeName {
                    Text(place)
                        .font(font(size: supportingSize * 0.9, isBold: false))
                        .lineLimit(1)
                        .opacity(0.9)
                }
            }
        } else {
            Text(weather == nil ? "Weather not set up" : "Weather out of date")
                .font(font(size: supportingSize, isBold: false))
                .opacity(0.9)
        }
    }

    /// The weather widget's own headline is the temperature, so it takes the
    /// headline size unless the clock is already using it.
    private var weatherTemperatureSize: CGFloat {
        settings.showsTime ? supportingSize * 1.4 : headlineSize
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarRows: some View {
        let style = settings.calendarStyle
        // A small family has room for one of the two, and the grid is the one
        // that is still readable at that size.
        let showsGrid = style.showsGrid
        let showsEvents = style.showsEvents && !(isCompact && style == .both)

        if showsGrid {
            MonthGridView(
                date: date,
                settings: settings,
                size: supportingSize,
                fontPostScriptName: settings.fontPostScriptName,
                accent: WidgetTextColor.color(hex: settings.textColorHex)
            )
            .frame(maxWidth: gridWidth)
        }
        if showsEvents {
            eventRows
        }
    }

    /// The grid is a table of digits, so it is sized by its content rather
    /// than stretched across a wide widget.
    private var gridWidth: CGFloat { min(width - 24, 7 * (supportingSize * 1.9)) }

    @ViewBuilder
    private var eventRows: some View {
        if calendarSnapshot == nil {
            // No file yet: the app has not read the calendar since this widget
            // was set up. That is not the same as being refused, and must not
            // read like it.
            Text("Open ShotDex to read today")
                .font(font(size: supportingSize * 0.9, isBold: false))
                .opacity(0.9)
        } else if let snapshot = calendarSnapshot, snapshot.hasAccess {
            if let events = snapshot.events(on: date), !events.isEmpty {
                let visible = CalendarFormat.visibleEvents(
                    events, limit: isCompact ? min(settings.maximumEventCount, 2) : settings.maximumEventCount
                )
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visible.shown) { event in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(WidgetTextColor.color(hex: event.colorHex ?? settings.textColorHex))
                                .frame(width: 5, height: 5)
                            Text(CalendarFormat.timeString(for: event))
                                .font(font(size: supportingSize * 0.9, isBold: false))
                                .monospacedDigit()
                                .opacity(0.9)
                            Text(event.title)
                                .font(font(size: supportingSize * 0.9, isBold: false))
                                .lineLimit(1)
                        }
                    }
                    if visible.remaining > 0 {
                        Text("+\(visible.remaining) more")
                            .font(font(size: supportingSize * 0.85, isBold: false))
                            .opacity(0.85)
                    }
                }
            } else {
                Text(snapshot.events(on: date) == nil ? "Open ShotDex for today" : "Nothing on today")
                    .font(font(size: supportingSize * 0.9, isBold: false))
                    .opacity(0.9)
            }
        } else {
            Text("Calendar access is off")
                .font(font(size: supportingSize * 0.9, isBold: false))
                .opacity(0.9)
        }
    }

    // MARK: Shared

    private func font(size: CGFloat, isBold: Bool) -> Font {
        .widgetClock(
            postScriptName: settings.fontPostScriptName,
            size: size,
            isBold: isBold,
            usesMonospacedDigits: settings.usesMonospacedDigits
        )
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch settings.placement {
        case .topLeading, .bottomLeading: .leading
        case .top, .center, .bottom: .center
        }
    }

    private var textAlignment: TextAlignment {
        switch settings.placement {
        case .topLeading, .bottomLeading: .leading
        case .top, .center, .bottom: .center
        }
    }
}

/// The month, as a grid, with today ringed. Draws `MonthGrid.Layout`, which
/// does all of the arithmetic.
struct MonthGridView: View {
    let date: Date
    let settings: PhotoWidgetSettings
    let size: CGFloat
    let fontPostScriptName: String
    let accent: Color

    var body: some View {
        let layout = MonthGrid.layout(
            for: date,
            weekStartsOnMonday: settings.weekStartsOnMonday
        )
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(layout.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.widgetClock(
                            postScriptName: fontPostScriptName,
                            size: size * 0.72,
                            isBold: false,
                            usesMonospacedDigits: true
                        ))
                        .opacity(0.75)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks(of: layout).enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, day in
                        let index = weekIndex * 7 + dayIndex
                        dayCell(day: day, isToday: index == layout.todayIndex)
                    }
                }
            }
        }
    }

    private func dayCell(day: Int?, isToday: Bool) -> some View {
        Text(day.map(String.init) ?? " ")
            .font(.widgetClock(
                postScriptName: fontPostScriptName,
                size: size * 0.82,
                isBold: isToday,
                usesMonospacedDigits: true
            ))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .background {
                // Today is a filled pill in the text colour, with the day
                // number knocked out of it — legible over any photo, and the
                // only marker the grid needs.
                if isToday {
                    Capsule().fill(accent.opacity(0.9))
                }
            }
            .foregroundStyle(isToday ? Color.black : accent)
    }

    private func weeks(of layout: MonthGrid.Layout) -> [[Int?]] {
        stride(from: 0, to: layout.days.count, by: 7).map {
            Array(layout.days[$0..<min($0 + 7, layout.days.count)])
        }
    }
}

/// The gradient behind the text when a photo is too busy for a shadow. It
/// follows the placement, so the dark end is always under the text.
struct PhotoWidgetScrim: View {
    let placement: PhotoWidgetSettings.Placement

    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.55), .black.opacity(0.0)],
            startPoint: start,
            endPoint: end
        )
    }

    private var start: UnitPoint {
        switch placement {
        case .topLeading, .top: .top
        case .center: .center
        case .bottom, .bottomLeading: .bottom
        }
    }

    private var end: UnitPoint {
        switch placement {
        case .topLeading, .top: .center
        case .center: .bottom
        case .bottom, .bottomLeading: .center
        }
    }
}

extension PhotoWidgetSettings.Placement {
    /// The alignment this placement means, shared by the widget and the
    /// Settings preview.
    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        case .bottomLeading: .bottomLeading
        }
    }
}
