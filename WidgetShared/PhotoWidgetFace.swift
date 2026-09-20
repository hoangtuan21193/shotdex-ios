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
            // An event line is cut, never shrunk: the face allows shrinking so
            // a long clock format still fits, but applying that to a list made
            // the titles a different size from the times beside them.
            eventRows
                .minimumScaleFactor(1)
        }
    }

    /// The grid is a table of digits, so it is sized by its content rather
    /// than stretched across a wide widget.
    private var gridWidth: CGFloat { min(rowWidth, 7 * (supportingSize * 1.9)) }

    /// Width available to a line of text: the widget less the margins the
    /// system gives its content, and less the preview's own padding.
    private var rowWidth: CGFloat { max(40, width - 32) }

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
                let limit = CalendarFormat.eventLimit(
                    isCompact: isCompact,
                    showsGrid: settings.calendarStyle.showsGrid,
                    maximum: settings.maximumEventCount
                )
                let visible = CalendarFormat.visibleEvents(events, limit: limit)
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
                                .fixedSize()
                            // The title is the only part that may be cut, and
                            // it is cut rather than allowed to widen the row:
                            // a long event name used to push the whole line
                            // past both edges of the widget, taking the
                            // colour dot off the left with it.
                            Text(event.title)
                                .font(font(size: supportingSize * 0.9, isBold: false))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        // Every row is bounded by the widget, not by its own
                        // longest title: an unbounded row grew past both edges
                        // and took the colour dot off the left with it.
                        .frame(width: rowWidth, alignment: .leading)
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
        if settings.anchor.isLeading { return .leading }
        if settings.anchor.isTrailing { return .trailing }
        return .center
    }

    private var textAlignment: TextAlignment {
        if settings.anchor.isLeading { return .leading }
        if settings.anchor.isTrailing { return .trailing }
        return .center
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
/// follows the text, so the dark end is always under it wherever it was
/// dragged.
struct PhotoWidgetScrim: View {
    let anchor: PhotoWidgetSettings.Anchor

    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.55), .black.opacity(0.0)],
            startPoint: start,
            endPoint: end
        )
    }

    /// Text in the top third darkens downward, text in the bottom third
    /// upward, and text in the middle gets an even wash — a gradient with both
    /// ends in the middle would be a flat black band.
    private var start: UnitPoint {
        if anchor.y < 0.34 { return .top }
        if anchor.y > 0.66 { return .bottom }
        return .center
    }

    private var end: UnitPoint {
        if anchor.y < 0.34 { return .center }
        if anchor.y > 0.66 { return .center }
        return .bottom
    }
}

extension PhotoWidgetSettings.Anchor {
    /// The alignment this anchor rounds to, for the stack that holds the text.
    /// The fine position is applied as an offset on top of it, so a block
    /// dragged near an edge stays inside the widget rather than hanging off it.
    var alignment: Alignment {
        let horizontal: HorizontalAlignment = isLeading ? .leading : (isTrailing ? .trailing : .center)
        let vertical: VerticalAlignment = y < 0.34 ? .top : (y > 0.66 ? .bottom : .center)
        return Alignment(horizontal: horizontal, vertical: vertical)
    }

    /// How far from that alignment the block actually sits, in points, given
    /// the space it is placed in and the size it takes up. Pure arithmetic, so
    /// the widget and the Settings preview cannot drift apart.
    func offset(in size: CGSize, contentSize: CGSize, inset: CGFloat) -> CGSize {
        let available = CGSize(
            width: max(0, size.width - contentSize.width - inset * 2),
            height: max(0, size.height - contentSize.height - inset * 2)
        )
        let targetX = available.width * x
        let targetY = available.height * y
        // The alignment already places the block at one of three stops; the
        // offset is the distance from that stop to where it was dragged.
        let stopX: CGFloat = isLeading ? 0 : (isTrailing ? available.width : available.width / 2)
        let stopY: CGFloat = y < 0.34 ? 0 : (y > 0.66 ? available.height : available.height / 2)
        return CGSize(width: targetX - stopX, height: targetY - stopY)
    }
}

/// The photo behind a widget, filled, zoomed and shifted the way the user
/// framed it in Settings.
///
/// Both processes draw it with this view: a photo that sits differently in the
/// preview than in the widget makes the preview a lie, and the whole point of
/// pinching it in Settings is to choose what the widget shows.
struct PhotoWidgetImageLayer: View {
    let image: Image
    let settings: PhotoWidgetSettings

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(1, min(settings.photoScale, PhotoWidgetSettings.maximumPhotoScale))
            // The overflow a zoomed photo has to give away in each direction,
            // halved because it spills both ways.
            let slackX = size.width * (scale - 1) / 2
            let slackY = size.height * (scale - 1) / 2
            image
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .offset(
                    x: slackX * settings.photoOffsetX,
                    y: slackY * settings.photoOffsetY
                )
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }
}
