import Foundation

/// The four widgets that draw something over a photo the user picked: a clock,
/// a calendar, the weather, and one that carries all three.
///
/// They are one family rather than four unrelated widgets because they differ
/// only in which rows they draw: every one of them needs a picture, a
/// typeface, a colour, a position and the same legibility treatment, and a
/// user who set up one expects the next to work the same way.
enum PhotoWidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock
    case calendar
    case weather
    case combined

    var id: String { rawValue }

    /// Shown in Settings and in the widget gallery.
    var title: String {
        switch self {
        case .clock: "Clock"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .combined: "Time, Date and Weather"
        }
    }

    /// WidgetKit's `kind`. Stable strings — changing one orphans every widget
    /// a user has already placed.
    var widgetKind: String {
        switch self {
        case .clock: "ShotDexClock"
        case .calendar: "ShotDexCalendar"
        case .weather: "ShotDexWeather"
        case .combined: "ShotDexCombined"
        }
    }

    /// Folder inside the App Group holding this widget's rendered pictures.
    var directoryName: String { "photo-widget-\(rawValue)" }

    /// Whether this widget ever needs the weather fetched for it. The app only
    /// asks for a location, and only talks to a weather service, when one of
    /// these is configured — the network call is the user's choice, made by
    /// setting the widget up.
    var needsWeather: Bool { self == .weather || self == .combined }

    /// Whether it needs the calendar read.
    var needsCalendarEvents: Bool { self == .calendar || self == .combined }
}

/// Everything the user chose for one of those widgets, in a file both
/// processes read. Written by Settings, read by the widget on every timeline
/// build.
///
/// It carries no photo of its own: the pictures live beside it as small JPEGs
/// (`PhotoWidgetSnapshot`), because the widget cannot reach the photo library
/// and a widget process must not decode a full-resolution image.
struct PhotoWidgetSettings: Codable, Equatable {
    /// Where the background picture comes from.
    enum Source: Codable, Equatable, Hashable {
        /// One photo the user picked.
        case photo(assetId: String)
        /// An album, shown one photo at a time.
        case album(collectionId: String, title: String)
        /// No picture — the widget on a plain background.
        case none
    }

    /// How often an album source moves to the next photo.
    enum Rotation: String, Codable, CaseIterable, Identifiable {
        case hourly
        case daily
        case never

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hourly: "Every Hour"
            case .daily: "Every Day"
            case .never: "Never"
            }
        }
    }

    /// Where the text sits on the photo.
    enum Placement: String, Codable, CaseIterable, Identifiable {
        case topLeading
        case top
        case center
        case bottom
        case bottomLeading

        var id: String { rawValue }

        var title: String {
            switch self {
            case .topLeading: "Top Left"
            case .top: "Top"
            case .center: "Centre"
            case .bottom: "Bottom"
            case .bottomLeading: "Bottom Left"
            }
        }
    }

    /// How the text is kept readable over a photo.
    enum Legibility: String, Codable, CaseIterable, Identifiable {
        /// Nothing behind the text.
        case none
        /// A soft drop shadow — enough on most photos, costs no contrast.
        case shadow
        /// A gradient scrim behind the text block, for busy photos.
        case scrim

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .shadow: "Shadow"
            case .scrim: "Scrim"
            }
        }
    }

    /// What the calendar row shows.
    enum CalendarStyle: String, Codable, CaseIterable, Identifiable {
        /// The month, as a grid, with today marked.
        case monthGrid
        /// What is on today, from the user's own calendars.
        case events
        /// The grid, with today's events under it (large families only; the
        /// smaller ones fall back to the grid).
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .monthGrid: "Month"
            case .events: "Today's Events"
            case .both: "Month and Events"
            }
        }

        var showsGrid: Bool { self != .events }
        var showsEvents: Bool { self != .monthGrid }
    }

    enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
        case system
        case celsius
        case fahrenheit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .celsius: "Celsius"
            case .fahrenheit: "Fahrenheit"
            }
        }
    }

    var source: Source = .none
    var rotation: Rotation = .daily

    var showsTime = true
    var showsDate = true
    /// A `DateFormatter` pattern, or empty for `timeStyle = .short`. Seconds are
    /// rejected when it is stored: a widget is refreshed by the system at most
    /// once a minute, so a seconds field would read as a stopped clock.
    var timeFormat = ""
    /// A `DateFormatter` pattern, or empty for `dateStyle = .medium`.
    var dateFormat = ""

    var calendarStyle: CalendarStyle = .monthGrid
    /// How many of today's events are listed before the row says "+N more".
    var maximumEventCount = 3
    /// Weekday the month grid starts on, or nil for the region's own.
    var weekStartsOnMonday = false

    var temperatureUnit: TemperatureUnit = .system
    /// Show the day's high and low under the current temperature.
    var showsHighLow = true
    /// Show the place the weather is for.
    var showsWeatherPlace = true

    /// PostScript name of the typeface, or empty for the system font.
    var fontPostScriptName = ""
    /// Shown in Settings; a PostScript name is not a name a person reads.
    var fontDisplayName = "System"
    /// Point size of the headline row at the medium family; the other families
    /// scale from it (`scaledHeadlineSize`).
    var timeSize: Double = 34
    /// Point size of the supporting rows.
    var dateSize: Double = 13
    /// `true` draws the headline in a heavier weight, for the system font only —
    /// a chosen face already carries its own weight.
    var isBold = false
    /// Digits keep one width, so the clock does not jitter as it ticks.
    var usesMonospacedDigits = true

    /// `#RRGGBB`. Stored as a string because the file is read by two targets
    /// and neither should have to agree on a colour type.
    var textColorHex = "#FFFFFF"
    var placement: Placement = .bottomLeading
    var legibility: Legibility = .shadow
    /// 0…1 — how much the photo is dimmed under the whole widget.
    var photoDimming: Double = 0.1

    init() {}

    /// Decoded field by field, with every value falling back to its default.
    ///
    /// The synthesised decoder fails the whole file when one key is missing,
    /// which would mean a settings file written by an older build — or by the
    /// version that only had a clock — throwing away everything the user set
    /// up. A widget's settings are small and worth keeping.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let defaults = PhotoWidgetSettings()
        source = value(.source, defaults.source)
        rotation = value(.rotation, defaults.rotation)
        showsTime = value(.showsTime, defaults.showsTime)
        showsDate = value(.showsDate, defaults.showsDate)
        timeFormat = value(.timeFormat, defaults.timeFormat)
        dateFormat = value(.dateFormat, defaults.dateFormat)
        calendarStyle = value(.calendarStyle, defaults.calendarStyle)
        maximumEventCount = value(.maximumEventCount, defaults.maximumEventCount)
        weekStartsOnMonday = value(.weekStartsOnMonday, defaults.weekStartsOnMonday)
        temperatureUnit = value(.temperatureUnit, defaults.temperatureUnit)
        showsHighLow = value(.showsHighLow, defaults.showsHighLow)
        showsWeatherPlace = value(.showsWeatherPlace, defaults.showsWeatherPlace)
        fontPostScriptName = value(.fontPostScriptName, defaults.fontPostScriptName)
        fontDisplayName = value(.fontDisplayName, defaults.fontDisplayName)
        timeSize = value(.timeSize, defaults.timeSize)
        dateSize = value(.dateSize, defaults.dateSize)
        isBold = value(.isBold, defaults.isBold)
        usesMonospacedDigits = value(.usesMonospacedDigits, defaults.usesMonospacedDigits)
        textColorHex = value(.textColorHex, defaults.textColorHex)
        placement = value(.placement, defaults.placement)
        legibility = value(.legibility, defaults.legibility)
        photoDimming = value(.photoDimming, defaults.photoDimming)
    }

    static let `default` = PhotoWidgetSettings()

    /// The defaults each widget opens on. A calendar with the time on it is
    /// not what "Calendar" means, and a weather widget whose headline is the
    /// clock would be a clock — so each kind starts with the rows it is named
    /// after, and the user can still turn the others on.
    static func `default`(for kind: PhotoWidgetKind) -> PhotoWidgetSettings {
        var settings = PhotoWidgetSettings()
        switch kind {
        case .clock:
            break
        case .calendar:
            settings.showsTime = false
            settings.showsDate = true
            settings.dateSize = 15
            settings.placement = .bottom
        case .weather:
            settings.showsTime = false
            settings.showsDate = true
        case .combined:
            settings.timeSize = 30
            settings.calendarStyle = .events
            settings.maximumEventCount = 2
        }
        return settings
    }

    /// Sizes the pickers offer, and the bounds anything typed is clamped to.
    static let timeSizeRange: ClosedRange<Double> = 18...72
    static let dateSizeRange: ClosedRange<Double> = 9...28
    static let eventCountRange: ClosedRange<Int> = 1...5

    /// Point size for one widget family, relative to the medium one the user
    /// sized against. A small family is narrower, not a different design.
    func scaledHeadlineSize(forWidgetWidth width: Double) -> Double {
        guard width > 0 else { return timeSize }
        // 329 pt is the medium family's width on a 6.1" iPhone — the size the
        // preview in Settings shows, so what the user set is what they get
        // there and everything else is proportional to it.
        let scale = max(0.6, min(1.6, width / 329))
        return timeSize * scale
    }

    func scaledSupportingSize(forWidgetWidth width: Double) -> Double {
        guard width > 0 else { return dateSize }
        let scale = max(0.7, min(1.4, width / 329))
        return dateSize * scale
    }

    /// The album or photo this is showing, in words, for the Settings row.
    var sourceSummary: String {
        switch source {
        case .photo: "One photo"
        case .album(_, let title): title
        case .none: "No photo"
        }
    }
}

/// Every widget's settings in one file, keyed by kind.
///
/// One file rather than four: Settings writes them all through the same store,
/// and a widget reading a file that a half-finished write left behind is a
/// class of bug worth not having four times.
struct PhotoWidgetSettingsFile: Codable, Equatable {
    var byKind: [String: PhotoWidgetSettings]

    static let fileName = "photo-widgets.json"

    static var `default`: PhotoWidgetSettingsFile {
        PhotoWidgetSettingsFile(
            byKind: Dictionary(
                uniqueKeysWithValues: PhotoWidgetKind.allCases.map {
                    ($0.rawValue, PhotoWidgetSettings.default(for: $0))
                }
            )
        )
    }

    subscript(kind: PhotoWidgetKind) -> PhotoWidgetSettings {
        get { byKind[kind.rawValue] ?? .default(for: kind) }
        set { byKind[kind.rawValue] = newValue }
    }

    static func read() -> PhotoWidgetSettingsFile {
        guard let container = WidgetSharedContainer.url else { return .default }
        let url = container.appendingPathComponent(fileName)
        if let file = WidgetSharedContainer.decode(PhotoWidgetSettingsFile.self, at: url) {
            return file
        }
        return migratedFromClockOnlyFile(in: container) ?? .default
    }

    static func settings(for kind: PhotoWidgetKind) -> PhotoWidgetSettings {
        read()[kind]
    }

    /// The first version of this feature shipped a clock and nothing else, in
    /// `clock-settings.json`. A user who set that clock up keeps it.
    private static func migratedFromClockOnlyFile(in container: URL) -> PhotoWidgetSettingsFile? {
        let legacy = container.appendingPathComponent("clock-settings.json")
        guard let clock = WidgetSharedContainer.decode(PhotoWidgetSettings.self, at: legacy)
        else { return nil }
        var file = PhotoWidgetSettingsFile.default
        file[.clock] = clock
        return file
    }
}

/// Renders the time and date rows. Pure and calendar-injectable, so the
/// formats are unit-tested rather than eyeballed in a screenshot.
enum PhotoWidgetFormat {
    /// Patterns offered in Settings, in the order they are listed. An empty
    /// pattern means "whatever this region calls short" — the right default,
    /// and the only entry that follows a 24-hour system setting.
    static let timePresets: [(title: String, pattern: String)] = [
        ("System", ""),
        ("9:41", "h:mm"),
        ("9:41 AM", "h:mm a"),
        ("09:41", "HH:mm"),
        ("9.41", "h.mm"),
    ]

    static let datePresets: [(title: String, pattern: String)] = [
        ("System", ""),
        ("Fri 19 Sep", "EEE d MMM"),
        ("Friday, 19 September", "EEEE, d MMMM"),
        ("19/09/2026", "dd/MM/yyyy"),
        ("Sep 19", "MMM d"),
        ("2026-09-19", "yyyy-MM-dd"),
    ]

    /// A pattern the widget can honour: no seconds, and nothing longer than a
    /// line. A widget's timeline is rebuilt once a minute at best, so a
    /// seconds field would sit frozen on a wrong value.
    static func sanitized(pattern: String) -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("s"), !trimmed.contains("S") else {
            return String(trimmed.filter { $0 != "s" && $0 != "S" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.prefix(40))
    }

    static func timeString(
        for date: Date,
        settings: PhotoWidgetSettings,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        let pattern = sanitized(pattern: settings.timeFormat)
        if pattern.isEmpty {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        } else {
            formatter.dateFormat = pattern
        }
        return formatter.string(from: date)
    }

    static func dateString(
        for date: Date,
        settings: PhotoWidgetSettings,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        let pattern = sanitized(pattern: settings.dateFormat)
        if pattern.isEmpty {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        } else {
            formatter.dateFormat = pattern
        }
        return formatter.string(from: date)
    }
}

/// The pictures written for one photo widget: one for a single-photo source,
/// several for an album.
struct PhotoWidgetSnapshot: Codable, Equatable {
    struct Frame: Codable, Equatable {
        var assetId: String
        var fileName: String
    }

    var frames: [Frame]
    var generatedAt: Date

    static let empty = PhotoWidgetSnapshot(frames: [], generatedAt: .distantPast)
    static let fileName = "snapshot.json"
    /// How many album photos are kept on disk per widget. Twelve covers half a
    /// day of hourly rotation and costs about a megabyte.
    static let maxFrames = 12

    static func directoryURL(for kind: PhotoWidgetKind, in container: URL) -> URL {
        container.appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    static func read(kind: PhotoWidgetKind) -> PhotoWidgetSnapshot {
        guard let container = WidgetSharedContainer.url else { return .empty }
        return WidgetSharedContainer.decode(
            PhotoWidgetSnapshot.self,
            at: directoryURL(for: kind, in: container).appendingPathComponent(fileName)
        ) ?? .empty
    }

    /// Which frame is showing at `date`. Pure, so the rotation is tested
    /// rather than watched for an hour.
    static func frameIndex(
        at date: Date,
        count: Int,
        rotation: PhotoWidgetSettings.Rotation,
        calendar: Calendar = .current
    ) -> Int? {
        guard count > 0 else { return nil }
        switch rotation {
        case .never:
            return 0
        case .hourly:
            let hours = Int(date.timeIntervalSince1970 / 3600)
            return ((hours % count) + count) % count
        case .daily:
            let days = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            return ((days % count) + count) % count
        }
    }

    func imageURL(at index: Int, kind: PhotoWidgetKind) -> URL? {
        guard frames.indices.contains(index), let container = WidgetSharedContainer.url
        else { return nil }
        return Self.directoryURL(for: kind, in: container)
            .appendingPathComponent(frames[index].fileName)
    }
}
