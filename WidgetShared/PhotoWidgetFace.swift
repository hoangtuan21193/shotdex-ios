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
    /// Widget width in points; every size scales from it.
    let width: Double
    var weather: WeatherSnapshot?
    var calendarSnapshot: CalendarSnapshot?
    /// Tall families get the grid and the event list; a small one has room for
    /// one of them.
    var isCompact = false
    /// Which pieces this instance draws. Nil means all of them, which is what
    /// a widget that has never been rearranged still does.
    var components: [PhotoWidgetComponent]?
    /// Set when the colour was worked out from the picture under *this* block
    /// — the Smart swatch. Nil means the user chose a fixed colour, and the
    /// hex in the settings is the answer.
    var textColor: Color?

    private var resolvedColor: Color {
        textColor ?? WidgetTextColor.color(hex: settings.textColorHex)
    }

    private var headlineSize: CGFloat {
        settings.scaledHeadlineSize(forWidgetWidth: width) * settings.scale(for: .time)
    }
    private var supportingSize: CGFloat { settings.scaledSupportingSize(forWidgetWidth: width) }
    private func supportingSize(for component: PhotoWidgetComponent) -> CGFloat {
        supportingSize * settings.scale(for: component)
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 4) {
            if draws(.time) {
                Text(PhotoWidgetFormat.timeString(for: date, settings: settings))
                    .font(font(size: headlineSize, isBold: settings.isBold))
                    .reportsComponentFrame(.time)
            }
            if draws(.date) {
                Text(PhotoWidgetFormat.dateString(for: date, settings: settings))
                    .font(font(size: supportingSize(for: .date), isBold: false))
                    .reportsComponentFrame(.date)
            }
            if draws(.weather) {
                weatherRow.reportsComponentFrame(.weather)
            }
            if draws(.calendar) {
                calendarRows.reportsComponentFrame(.calendar)
            }
            if isEmpty {
                // A widget with every row off would be an empty rectangle the
                // user cannot tell from a broken one.
                Text("ShotDex")
                    .font(font(size: supportingSize, isBold: false))
            }
        }
        .foregroundStyle(resolvedColor)
        .shadow(
            color: .black.opacity(settings.legibility == .shadow ? 0.55 : 0),
            radius: 4,
            y: 1
        )
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(textAlignment)
    }

    /// Whether this instance draws a given piece: the widget's own rules
    /// first, then the filter that lets one group be drawn on its own.
    private func draws(_ component: PhotoWidgetComponent) -> Bool {
        guard component.isOn(in: settings) else { return false }
        guard let components else { return true }
        return components.contains(component)
    }

    private var isEmpty: Bool {
        !PhotoWidgetComponent.allCases.contains(where: draws)
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
                        .font(font(size: supportingSize(for: .weather), isBold: false))
                        .lineLimit(1)
                }
                if settings.showsHighLow,
                   let highLow = WeatherFormat.highLowString(
                       highCelsius: weather.highCelsius,
                       lowCelsius: weather.lowCelsius,
                       unit: settings.temperatureUnit
                   ) {
                    Text(highLow)
                        .font(font(size: supportingSize(for: .weather) * 0.9, isBold: false))
                        .monospacedDigit()
                }
                if settings.showsWeatherPlace, let place = weather.placeName {
                    Text(place)
                        .font(font(size: supportingSize(for: .weather) * 0.9, isBold: false))
                        .lineLimit(1)
                        .opacity(0.9)
                }
            }
        } else {
            Text(weather == nil ? "Weather not set up" : "Weather out of date")
                .font(font(size: supportingSize(for: .weather), isBold: false))
                .opacity(0.9)
        }
    }

    /// The weather widget's own headline is the temperature, so it takes the
    /// headline size unless the clock is already using it.
    private var weatherTemperatureSize: CGFloat {
        settings.showsTime
            ? supportingSize(for: .weather) * 1.4
            : settings.scaledHeadlineSize(forWidgetWidth: width) * settings.scale(for: .weather)
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
                size: supportingSize(for: .calendar),
                fontPostScriptName: settings.fontPostScriptName,
                accent: resolvedColor
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
    private var gridWidth: CGFloat { min(rowWidth, 7 * (supportingSize(for: .calendar) * 1.9)) }

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
                                .fill(event.colorHex.map { WidgetTextColor.color(hex: $0) } ?? resolvedColor)
                                .frame(width: 5, height: 5)
                            Text(CalendarFormat.timeString(for: event))
                                .font(font(size: supportingSize(for: .calendar) * 0.9, isBold: false))
                                .monospacedDigit()
                                .opacity(0.9)
                                .fixedSize()
                            // The title is the only part that may be cut, and
                            // it is cut rather than allowed to widen the row:
                            // a long event name used to push the whole line
                            // past both edges of the widget, taking the
                            // colour dot off the left with it.
                            Text(event.title)
                                .font(font(size: supportingSize(for: .calendar) * 0.9, isBold: false))
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
                            .font(font(size: supportingSize(for: .calendar) * 0.85, isBold: false))
                            .opacity(0.85)
                    }
                }
            } else {
                Text(snapshot.events(on: date) == nil ? "Open ShotDex for today" : "Nothing on today")
                    .font(font(size: supportingSize(for: .calendar) * 0.9, isBold: false))
                    .opacity(0.9)
            }
        } else {
            Text("Calendar access is off")
                .font(font(size: supportingSize(for: .calendar) * 0.9, isBold: false))
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
    /// Width ÷ height of the picture. Needed because a filled photo is
    /// already cropped before any zoom: a 3:2 frame in a square widget hides a
    /// third of itself, and that hidden part is what a two-finger drag should
    /// be able to bring into view. Defaults to 1, which behaves as the old
    /// zoom-only maths did.
    var aspectRatio: Double = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(1, min(settings.photoScale, PhotoWidgetSettings.maximumPhotoScale))
            let slack = PhotoWidgetImageLayer.slack(
                in: size, aspectRatio: aspectRatio, scale: scale
            )
            image
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .offset(
                    x: slack.width * settings.photoOffsetX,
                    y: slack.height * settings.photoOffsetY
                )
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    /// How far the picture can move in each direction before an edge shows.
    ///
    /// Half the overflow: the part the fill already cropped, plus whatever the
    /// zoom added. Pure, so "can I still drag this at 1×" is a test.
    static func slack(in size: CGSize, aspectRatio: Double, scale: Double) -> CGSize {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return .zero }
        let frameAspect = size.width / size.height
        // scaledToFill matches the short side, so the long side overflows.
        let filled: CGSize = aspectRatio > frameAspect
            ? CGSize(width: size.height * aspectRatio, height: size.height)
            : CGSize(width: size.width, height: size.width / aspectRatio)
        return CGSize(
            width: max(0, (filled.width * scale - size.width) / 2),
            height: max(0, (filled.height * scale - size.height) / 2)
        )
    }
}

/// Where each piece of the face ended up, so the editor can put a finger on
/// the exact line rather than on the stack it belongs to.
///
/// Selecting used to hit-test against the group, which meant tapping the date
/// selected the clock — the first piece in the stack — and there was no way to
/// reach anything below the first line at all.
struct PhotoWidgetComponentFrames: PreferenceKey {
    static let defaultValue: [PhotoWidgetComponent: CGRect] = [:]

    static func reduce(
        value: inout [PhotoWidgetComponent: CGRect],
        nextValue: () -> [PhotoWidgetComponent: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The coordinate space every reported frame is measured in.
enum PhotoWidgetFaceSpace {
    static let name = "photoWidgetFace"
}

extension View {
    func reportsComponentFrame(_ component: PhotoWidgetComponent) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PhotoWidgetComponentFrames.self,
                    value: [component: proxy.frame(in: .named(PhotoWidgetFaceSpace.name))]
                )
            }
        }
    }
}
