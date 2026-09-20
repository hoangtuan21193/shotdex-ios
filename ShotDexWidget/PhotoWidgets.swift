import SwiftUI
import WidgetKit

/// The four widgets that draw over a photo the user chose: a clock, a
/// calendar, the weather, and one carrying all three.
///
/// They share a provider and a view, and differ only in their `kind`: the
/// settings file says what each one draws, and everything it draws — the
/// picture, the events, the weather — was written into the App Group by the
/// app. The extension reads files and nothing else. No PhotoKit, no EventKit,
/// no network, no location.
struct PhotoWidgetEntry: TimelineEntry {
    let date: Date
    let kind: PhotoWidgetKind
    let settings: PhotoWidgetSettings
    let image: Image?
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
}

struct PhotoWidgetProvider: TimelineProvider {
    let kind: PhotoWidgetKind

    /// One entry a minute for an hour when a clock is on show. A widget cannot
    /// redraw on its own, and `Text(date, style: .time)` — the free live clock
    /// — cannot honour a custom format, which is the point of these widgets.
    /// It is also why a seconds field is rejected when the format is stored.
    private static let clockEntries = 60
    /// Without a clock, the face only changes with the data behind it, so it
    /// steps every quarter of an hour instead.
    private static let quietEntries = 8
    private static let quietStep = 15

    func placeholder(in context: Context) -> PhotoWidgetEntry {
        entry(for: .now, settings: PhotoWidgetSettings.default(for: kind), payload: Payload())
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoWidgetEntry) -> Void) {
        let payload = Payload()
        completion(entry(for: .now, settings: payload.settings[kind], payload: payload))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoWidgetEntry>) -> Void) {
        let calendar = Calendar.current
        let start = calendar.date(bySetting: .second, value: 0, of: .now) ?? .now
        // One pass over the files for the whole timeline, and one decode per
        // distinct picture in it. Reading them per entry would decode the same
        // JPEG sixty times to draw sixty different minutes of the same photo.
        let payload = Payload()
        let settings = payload.settings[kind]
        let showsClock = settings.showsTime
        let count = showsClock ? Self.clockEntries : Self.quietEntries
        let step = showsClock ? 1 : Self.quietStep

        let entries = (0..<count).compactMap { index -> PhotoWidgetEntry? in
            guard let date = calendar.date(byAdding: .minute, value: index * step, to: start)
            else { return nil }
            return entry(for: date, settings: settings, payload: payload)
        }
        let end = entries.last?.date ?? .now
        completion(Timeline(entries: entries, policy: .after(end)))
    }

    /// Everything read off disk once per timeline build, with the pictures
    /// decoded lazily and kept.
    private final class Payload {
        let settings = PhotoWidgetSettingsFile.read()
        let weather = WeatherSnapshot.read()
        let calendarSnapshot = CalendarSnapshot.read()
        private var images: [String: Image] = [:]

        func image(for kind: PhotoWidgetKind, at date: Date, rotation: PhotoWidgetSettings.Rotation) -> Image? {
            let snapshot = snapshot(for: kind)
            guard let index = PhotoWidgetSnapshot.frameIndex(
                at: date, count: snapshot.frames.count, rotation: rotation
            ) else { return nil }
            let key = "\(kind.rawValue)-\(index)"
            if let cached = images[key] { return cached }
            guard let url = snapshot.imageURL(at: index, kind: kind),
                  let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data)
            else { return nil }
            let image = Image(uiImage: uiImage)
            images[key] = image
            return image
        }

        private var snapshots: [PhotoWidgetKind: PhotoWidgetSnapshot] = [:]

        private func snapshot(for kind: PhotoWidgetKind) -> PhotoWidgetSnapshot {
            if let cached = snapshots[kind] { return cached }
            let snapshot = PhotoWidgetSnapshot.read(kind: kind)
            snapshots[kind] = snapshot
            return snapshot
        }
    }

    private func entry(
        for date: Date,
        settings: PhotoWidgetSettings,
        payload: Payload
    ) -> PhotoWidgetEntry {
        PhotoWidgetEntry(
            date: date,
            kind: kind,
            settings: settings,
            image: payload.image(for: kind, at: date, rotation: settings.rotation),
            weather: payload.weather,
            calendarSnapshot: payload.calendarSnapshot
        )
    }
}

/// One widget per kind. Declared separately because WidgetKit needs a distinct
/// type and a distinct `kind` string for each.
struct ClockPhotoWidget: Widget {
    var body: some WidgetConfiguration { PhotoWidgetConfiguration.make(kind: .clock) }
}

struct CalendarPhotoWidget: Widget {
    var body: some WidgetConfiguration { PhotoWidgetConfiguration.make(kind: .calendar) }
}

struct WeatherPhotoWidget: Widget {
    var body: some WidgetConfiguration { PhotoWidgetConfiguration.make(kind: .weather) }
}

struct CombinedPhotoWidget: Widget {
    var body: some WidgetConfiguration { PhotoWidgetConfiguration.make(kind: .combined) }
}

enum PhotoWidgetConfiguration {
    static func make(kind: PhotoWidgetKind) -> some WidgetConfiguration {
        StaticConfiguration(kind: kind.widgetKind, provider: PhotoWidgetProvider(kind: kind)) { entry in
            // The background is chosen inside the view, where the family is
            // known: a Lock Screen accessory has no photo behind it, and
            // painting one there would show as a grey block.
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName(kind.title)
        .description(description(for: kind))
        .supportedFamilies(families(for: kind))
    }

    /// Home Screen for every kind; the Lock Screen only for the two whose
    /// content survives being drawn without a photo, in one colour, in a strip
    /// the size of a sentence. A clock there would duplicate the Lock Screen's
    /// own clock, and the combined widget is three rows in a space with room
    /// for one.
    private static func families(for kind: PhotoWidgetKind) -> [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if kind.hasAccessoryFamilies {
            families += [.accessoryRectangular, .accessoryInline, .accessoryCircular]
        }
        return families
    }

    private static func description(for kind: PhotoWidgetKind) -> String {
        switch kind {
        case .clock: "The time over a photo you choose, in the style you set in ShotDex."
        case .calendar: "The month, or what is on today, over a photo you choose."
        case .weather: "The weather where you are, over a photo you choose."
        case .combined: "The time, the day and the weather, over a photo you choose."
        }
    }
}

struct PhotoWidgetBackground: View {
    let entry: PhotoWidgetEntry

    var body: some View {
        ZStack {
            if let image = entry.image {
                // Clipped because a filled image is bigger than its frame, and
                // anything stacked on an unclipped one is laid out against the
                // overflow.
                GeometryReader { proxy in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                Color.black
            }
            if entry.settings.photoDimming > 0 {
                Color.black.opacity(entry.settings.photoDimming)
            }
            if entry.settings.legibility == .scrim {
                PhotoWidgetScrim(placement: entry.settings.placement)
            }
        }
    }
}

struct PhotoWidgetView: View {
    let entry: PhotoWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(widgetURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            // The Lock Screen draws these in one colour on the wallpaper, so
            // the typeface, colour, placement and photo the user set for the
            // Home Screen have nothing to act on here; only the data does.
            PhotoWidgetAccessoryView(entry: entry, family: family)
                .containerBackground(.clear, for: .widget)
        default:
            GeometryReader { proxy in
                PhotoWidgetFace(
                    date: entry.date,
                    settings: entry.settings,
                    kind: entry.kind,
                    width: proxy.size.width,
                    weather: entry.weather,
                    calendarSnapshot: entry.calendarSnapshot,
                    isCompact: family == .systemSmall
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: entry.settings.placement.alignment
                )
            }
            .containerBackground(for: .widget) {
                PhotoWidgetBackground(entry: entry)
            }
        }
    }

    /// A tap opens what the widget is showing: the photo itself when the user
    /// picked one, the app otherwise.
    private var widgetURL: URL? {
        switch entry.settings.source {
        case .photo(let assetId): WidgetDeepLink.photo(assetId: assetId).url
        case .album, .none: nil
        }
    }
}
