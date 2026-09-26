import Foundation

/// One saved look for the photo widget: a name, and everything that look sets.
///
/// This replaced four fixed widget kinds (Clock, Calendar, Weather, and one
/// that carried all three). They were never four widgets — they differed only
/// in which rows they started switched on, and the split actively took
/// something away, because a "Clock" could not be given the weather even
/// though the face draws it fine. A design can carry any of the rows, and a
/// user can keep as many designs as they have widgets.
///
/// The `id` is what a placed widget remembers, so renaming a design does not
/// orphan the widget showing it, and it is also the name of the folder that
/// design's rendered pictures live in.
struct PhotoWidgetDesign: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var settings: PhotoWidgetSettings

    init(id: String = UUID().uuidString, name: String, settings: PhotoWidgetSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }

    /// Folder inside the App Group holding this design's rendered pictures.
    var directoryName: String { PhotoWidgetDesign.directoryName(id: id) }

    static func directoryName(id: String) -> String { "photo-widget-\(id)" }

    /// What a design starts as: the time and the date over a photo. That is
    /// the widget people place most, and the weather and the calendar are one
    /// toggle away.
    static func makeDefault(name: String = "My Widget") -> PhotoWidgetDesign {
        PhotoWidgetDesign(name: name, settings: PhotoWidgetSettings())
    }
}

/// WidgetKit's `kind` for the one photo widget. A stable string — changing it
/// orphans every widget already placed.
enum PhotoWidgetIdentity {
    static let widgetKind = "ShotDexPhoto"
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

    /// Where the text sits on the photo, as a fraction of the widget: (0,0)
    /// is the top-left corner and (1,1) the bottom-right. A fraction rather
    /// than a corner because the user places it by dragging it, and what they
    /// drag it to is rarely one of five corners.
    struct Anchor: Codable, Equatable, Hashable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x.clampedToUnit
            self.y = y.clampedToUnit
        }

        static let topLeading = Anchor(x: 0, y: 0)
        static let center = Anchor(x: 0.5, y: 0.5)
        static let bottomLeading = Anchor(x: 0, y: 1)
        static let bottom = Anchor(x: 0.5, y: 1)

        /// Which way the lines line up under each other. Text dragged to the
        /// left edge reads as a left-aligned block; in the middle it reads as
        /// a centred one.
        var isLeading: Bool { x < 0.34 }
        var isTrailing: Bool { x > 0.66 }
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

    /// Whether the design carries the weather at all. Before designs this was
    /// implied by the widget's kind, which is exactly the restriction designs
    /// remove: a clock could not be given the weather even though the face
    /// draws it perfectly well.
    var showsWeather = false
    /// Whether it carries the month grid or today's events at all.
    /// `calendarStyle` then says which of the two.
    var showsCalendar = false

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
    /// Where the block of text sits, dragged by the user on the preview. Any
    /// piece without a position of its own sits here, which is what keeps a
    /// widget set up before the pieces could be separated looking the same.
    var anchor: Anchor = .bottomLeading
    /// Per-piece positions, keyed by `PhotoWidgetComponent.rawValue`. Pieces
    /// left out share `anchor` and stack together.
    var componentAnchors: [String: Anchor] = [:]
    /// Per-piece size, as a multiplier on the type sizes. The weather block
    /// and the calendar had no size of their own before this: the two sliders
    /// only reached the clock and the supporting lines.
    var componentScales: [String: Double] = [:]
    var legibility: Legibility = .shadow
    /// 0…1 — how much the photo is dimmed under the whole widget.
    var photoDimming: Double = 0.1

    /// How far the photo is zoomed past filling the widget, and where the
    /// zoomed photo is held. The user sets both by pinching and dragging the
    /// preview, and the widget applies the same numbers — the picture behind
    /// the clock is the part of it they framed, not whatever the middle
    /// happened to be.
    var photoScale: Double = 1
    /// -1…1 of the overflow in each direction; 0 keeps the photo centred.
    var photoOffsetX: Double = 0
    var photoOffsetY: Double = 0

    /// The Home Screen answer this widget has already taken in.
    ///
    /// The menu out there cannot be cleared by the app, so without this a
    /// photo picked once would go on overriding every later change made in
    /// ShotDex. Recorded when the menu's answer is applied, and compared on
    /// every timeline build: an answer that has not changed is not applied
    /// again, which leaves the app free to be the newer word.
    var appliedIntentSignature: String?

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
        showsWeather = value(.showsWeather, defaults.showsWeather)
        showsCalendar = value(.showsCalendar, defaults.showsCalendar)
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
        anchor = value(.anchor, defaults.anchor)
        componentAnchors = value(.componentAnchors, defaults.componentAnchors)
        componentScales = value(.componentScales, defaults.componentScales)
        legibility = value(.legibility, defaults.legibility)
        photoDimming = value(.photoDimming, defaults.photoDimming)
        appliedIntentSignature = try? container.decodeIfPresent(String.self, forKey: .appliedIntentSignature)
        photoScale = max(1, min(value(.photoScale, defaults.photoScale), PhotoWidgetSettings.maximumPhotoScale))
        photoOffsetX = value(.photoOffsetX, defaults.photoOffsetX).clampedToSigned
        photoOffsetY = value(.photoOffsetY, defaults.photoOffsetY).clampedToSigned

        // A file written before the text could be dragged named one of five
        // corners; that corner is where the drag starts from.
        if !container.contains(.anchor),
           let legacy = try? container.decodeIfPresent(String.self, forKey: .placement),
           let migrated = PhotoWidgetSettings.anchor(forLegacyPlacement: legacy) {
            anchor = migrated
        }
    }

    /// Written field by field, because `placement` is a key this type reads
    /// and never writes: it belongs to the version whose text sat in a corner.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(showsTime, forKey: .showsTime)
        try container.encode(showsDate, forKey: .showsDate)
        try container.encode(showsWeather, forKey: .showsWeather)
        try container.encode(showsCalendar, forKey: .showsCalendar)
        try container.encode(timeFormat, forKey: .timeFormat)
        try container.encode(dateFormat, forKey: .dateFormat)
        try container.encode(calendarStyle, forKey: .calendarStyle)
        try container.encode(maximumEventCount, forKey: .maximumEventCount)
        try container.encode(weekStartsOnMonday, forKey: .weekStartsOnMonday)
        try container.encode(temperatureUnit, forKey: .temperatureUnit)
        try container.encode(showsHighLow, forKey: .showsHighLow)
        try container.encode(showsWeatherPlace, forKey: .showsWeatherPlace)
        try container.encode(fontPostScriptName, forKey: .fontPostScriptName)
        try container.encode(fontDisplayName, forKey: .fontDisplayName)
        try container.encode(timeSize, forKey: .timeSize)
        try container.encode(dateSize, forKey: .dateSize)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(usesMonospacedDigits, forKey: .usesMonospacedDigits)
        try container.encode(textColorHex, forKey: .textColorHex)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(componentAnchors, forKey: .componentAnchors)
        try container.encode(componentScales, forKey: .componentScales)
        try container.encode(legibility, forKey: .legibility)
        try container.encode(photoDimming, forKey: .photoDimming)
        try container.encode(photoScale, forKey: .photoScale)
        try container.encode(photoOffsetX, forKey: .photoOffsetX)
        try container.encode(photoOffsetY, forKey: .photoOffsetY)
        try container.encodeIfPresent(appliedIntentSignature, forKey: .appliedIntentSignature)
    }

    /// The keys, spelled out because one of them is only ever read: a file
    /// from the version whose text sat in a corner still carries `placement`,
    /// and that is what the first drag starts from.
    enum CodingKeys: String, CodingKey {
        case source, rotation, showsTime, showsDate, timeFormat, dateFormat
        case showsWeather, showsCalendar
        case calendarStyle, maximumEventCount, weekStartsOnMonday
        case temperatureUnit, showsHighLow, showsWeatherPlace
        case fontPostScriptName, fontDisplayName, timeSize, dateSize
        case isBold, usesMonospacedDigits, textColorHex
        case anchor, componentAnchors, componentScales, legibility, photoDimming
        case photoScale, photoOffsetX, photoOffsetY
        case appliedIntentSignature
        case placement
    }

    /// How far a photo may be zoomed in the preview. Past this a widget-sized
    /// JPEG is being enlarged into mush.
    static let maximumPhotoScale: Double = 3

    static func anchor(forLegacyPlacement placement: String) -> Anchor? {
        switch placement {
        case "topLeading": Anchor(x: 0, y: 0)
        case "top": Anchor(x: 0.5, y: 0)
        case "center": .center
        case "bottom": .bottom
        case "bottomLeading": .bottomLeading
        default: nil
        }
    }

    /// Where one piece sits: its own position, or the shared one.
    func anchor(for component: PhotoWidgetComponent) -> Anchor {
        componentAnchors[component.rawValue] ?? anchor
    }

    /// Moves one piece. The first piece moved away from the shared position
    /// pins every other piece where it already was, so dragging the clock does
    /// not drag the date along behind it.
    mutating func setAnchor(_ newAnchor: Anchor, for component: PhotoWidgetComponent, in components: [PhotoWidgetComponent]) {
        for other in components where componentAnchors[other.rawValue] == nil {
            componentAnchors[other.rawValue] = anchor
        }
        componentAnchors[component.rawValue] = newAnchor
    }

    /// Back to one stack at the shared position, at the sizes the sliders set.
    mutating func resetComponentAnchors() {
        componentAnchors = [:]
        componentScales = [:]
    }

    /// How much bigger or smaller one piece is drawn than the type sizes say.
    func scale(for component: PhotoWidgetComponent) -> Double {
        min(max(componentScales[component.rawValue] ?? 1, Self.componentScaleRange.lowerBound),
            Self.componentScaleRange.upperBound)
    }

    mutating func setScale(_ scale: Double, for component: PhotoWidgetComponent) {
        let clamped = min(max(scale, Self.componentScaleRange.lowerBound),
                          Self.componentScaleRange.upperBound)
        // A piece at its natural size stores nothing, so "reset" is a delete
        // and the file does not fill with 1.0s.
        if abs(clamped - 1) < 0.01 {
            componentScales.removeValue(forKey: component.rawValue)
        } else {
            componentScales[component.rawValue] = clamped
        }
    }

    /// Half size to double. Past that a line either cannot be read or cannot
    /// fit in the widget it is on.
    static let componentScaleRange: ClosedRange<Double> = 0.5...2

    static let `default` = PhotoWidgetSettings()

    /// The four kinds this feature shipped as before designs, kept only so a
    /// file written by that version can be read once and turned into designs.
    /// Nothing outside `PhotoWidgetSettingsFile.migrated(from:)` should use it.
    enum LegacyKind: String, CaseIterable {
        case clock
        case calendar
        case weather
        case combined

        var title: String {
            switch self {
            case .clock: "Clock"
            case .calendar: "Calendar"
            case .weather: "Weather"
            case .combined: "Time, Date and Weather"
            }
        }

        var directoryName: String { "photo-widget-\(rawValue)" }

        /// What the kind used to imply, now that the two are stored flags.
        var showsWeather: Bool { self == .weather || self == .combined }
        var showsCalendar: Bool { self == .calendar || self == .combined }
    }

    /// The defaults the old kinds opened on, applied when their settings are
    /// turned into designs so a migrated design looks like what it replaced.
    static func `default`(for kind: LegacyKind) -> PhotoWidgetSettings {
        var settings = PhotoWidgetSettings()
        settings.showsWeather = kind.showsWeather
        settings.showsCalendar = kind.showsCalendar
        switch kind {
        case .clock:
            break
        case .calendar:
            settings.showsTime = false
            settings.showsDate = true
            settings.dateSize = 15
            settings.anchor = .bottom
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

/// Every design the user has made, in one file, in the order the Settings
/// list shows them.
///
/// An array rather than a dictionary: this is a list a person reorders and
/// renames, and a dictionary would have to carry the order alongside anyway.
/// One file rather than one per design, because a widget reading a file that a
/// half-finished write left behind is a class of bug worth not having twice.
struct PhotoWidgetSettingsFile: Codable, Equatable {
    var designs: [PhotoWidgetDesign]

    static let fileName = "photo-widgets.json"

    /// A file with nothing in it still has to answer a placed widget, so it
    /// answers with one default design.
    static var `default`: PhotoWidgetSettingsFile {
        PhotoWidgetSettingsFile(designs: [.makeDefault()])
    }

    /// The design a widget falls back to: the first one. A widget whose design
    /// was deleted, and one placed before it was ever configured, both land
    /// here rather than drawing nothing.
    var firstDesign: PhotoWidgetDesign { designs.first ?? .makeDefault() }

    func design(id: String?) -> PhotoWidgetDesign {
        guard let id, let match = designs.first(where: { $0.id == id }) else {
            return firstDesign
        }
        return match
    }

    subscript(id: String) -> PhotoWidgetSettings {
        get { design(id: id).settings }
        set {
            guard let index = designs.firstIndex(where: { $0.id == id }) else { return }
            designs[index].settings = newValue
        }
    }

    /// Reads the file, migrating an older one **and writing the result back**
    /// before returning it.
    ///
    /// Persisting the migration here is not tidiness, it is correctness: a
    /// design's `id` is a fresh UUID, so a migration that stayed in memory
    /// would mint different ids on every read. The store compares what it
    /// holds against what is on disk to pick up edits made in the Home
    /// Screen's menu, and two reads that never agree made that comparison
    /// always true — an observable change on every pass, an app that never
    /// went idle, and frames rendered into a folder named after an id that
    /// was already stale.
    static func read() -> PhotoWidgetSettingsFile {
        guard let container = WidgetSharedContainer.url else { return .default }
        let url = container.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            let file = PhotoWidgetSettingsFile.default
            file.write()
            return file
        }
        if let file = try? JSONDecoder().decode(PhotoWidgetSettingsFile.self, from: data),
           !file.designs.isEmpty {
            return file
        }
        // A file from before designs, or one whose design list came back
        // empty: rebuild it rather than hand back defaults over the top of
        // settings the user spent time on.
        let file = migrated(from: data) ?? .default
        file.write()
        return file
    }

    static func settings(id: String?) -> PhotoWidgetSettings {
        read().design(id: id).settings
    }

    /// Both processes write this file: the app when its Settings change, and
    /// the widget when the Home Screen's menu says something new. Last writer
    /// wins, which is what "change it in either place" means.
    func write() {
        guard let container = WidgetSharedContainer.url else { return }
        try? WidgetSharedContainer.encode(
            self, to: container.appendingPathComponent(Self.fileName)
        )
    }

    // MARK: Migration

    /// The shape this file had while there were four fixed widget kinds.
    private struct LegacyFile: Decodable {
        var byKind: [String: PhotoWidgetSettings]
    }

    /// Turns a pre-designs file into designs.
    ///
    /// Only the kinds the user actually set a photo on become designs — the
    /// other three were defaults nobody chose, and carrying them in would
    /// hand someone four list rows they never made. Each keeps the name its
    /// kind had, so a widget that said "Weather" is still called Weather, and
    /// the weather and calendar flags the kind used to imply become stored.
    static func migrated(from data: Data) -> PhotoWidgetSettingsFile? {
        guard let legacy = try? JSONDecoder().decode(LegacyFile.self, from: data) else {
            return nil
        }
        var designs: [PhotoWidgetDesign] = []
        for kind in PhotoWidgetSettings.LegacyKind.allCases {
            guard var settings = legacy.byKind[kind.rawValue], settings.source != .none else {
                continue
            }
            settings.showsWeather = kind.showsWeather
            settings.showsCalendar = kind.showsCalendar
            designs.append(PhotoWidgetDesign(name: kind.title, settings: settings))
        }
        guard !designs.isEmpty else { return .default }
        return PhotoWidgetSettingsFile(designs: designs)
    }

    /// Folders the pre-designs version rendered into. Nothing reads them once
    /// the designs exist, and each design re-renders into its own.
    static var legacyDirectoryNames: [String] {
        PhotoWidgetSettings.LegacyKind.allCases.map(\.directoryName)
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
    /// Longest edge these frames were rendered at. Missing on anything written
    /// before the size went up, which is exactly what marks it for redoing.
    var renderedPixels: Int?
    /// Which renderer wrote them. A frame from an older renderer is redone
    /// even when its size is right — version 1 wrote the blurred preview.
    var rendererVersion: Int?
    /// The album or photo these frames are of. A widget's own folder is reused
    /// only while it still holds the source the settings name; otherwise the
    /// per-album or per-photo folder is the one to read.
    var sourceId: String?

    static let empty = PhotoWidgetSnapshot(frames: [], generatedAt: .distantPast)

    /// True when these frames are smaller, or older, than what is drawn today.
    func isBelow(pixels: Int, rendererVersion current: Int = 0) -> Bool {
        (renderedPixels ?? 0) < pixels || (rendererVersion ?? 0) < current
    }
    static let fileName = "snapshot.json"
    /// How many album photos are kept on disk per widget. Twelve covers half a
    /// day of hourly rotation and costs about a megabyte.
    static let maxFrames = 12

    static func directoryURL(named name: String, in container: URL) -> URL {
        container.appendingPathComponent(name, isDirectory: true)
    }

    static func directoryURL(for design: PhotoWidgetDesign, in container: URL) -> URL {
        directoryURL(named: design.directoryName, in: container)
    }

    /// Where an album's frames live when a widget was pointed at it from the
    /// Home Screen. Keyed by album rather than by widget, because two widgets
    /// can be set to the same album and neither should pay for the other's
    /// copy — and because the identifier is what the widget carries.
    ///
    /// PhotoKit identifiers hold slashes (`ABCD-1234/L0/040`), which are path
    /// separators, so everything outside letters, digits and dashes becomes a
    /// dash.
    static func albumDirectoryName(albumId: String) -> String {
        let slug = albumId.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        return "photo-widget-album-" + String(slug).prefix(80)
    }

    /// Where one chosen photo's frame lives. Same slug rule as an album's
    /// folder, and a different prefix so the two can never collide.
    static func assetDirectoryName(assetId: String) -> String {
        let slug = assetId.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        return "photo-widget-asset-" + String(slug).prefix(80)
    }

    static func read(directoryName: String) -> PhotoWidgetSnapshot {
        guard let container = WidgetSharedContainer.url else { return .empty }
        return WidgetSharedContainer.decode(
            PhotoWidgetSnapshot.self,
            at: directoryURL(named: directoryName, in: container)
                .appendingPathComponent(fileName)
        ) ?? .empty
    }

    static func read(designId: String) -> PhotoWidgetSnapshot {
        read(directoryName: PhotoWidgetDesign.directoryName(id: designId))
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

    func imageURL(at index: Int, directoryName: String) -> URL? {
        guard frames.indices.contains(index), let container = WidgetSharedContainer.url
        else { return nil }
        return Self.directoryURL(named: directoryName, in: container)
            .appendingPathComponent(frames[index].fileName)
    }

    func imageURL(at index: Int, designId: String) -> URL? {
        imageURL(at: index, directoryName: PhotoWidgetDesign.directoryName(id: designId))
    }
}

private extension Double {
    /// 0…1, for the fractions that say where something sits.
    var clampedToUnit: Double { min(max(self, 0), 1) }
    /// -1…1, for the ones that say how far it is pushed either way.
    var clampedToSigned: Double { min(max(self, -1), 1) }
}
