import AppIntents
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
    /// Set when this widget was pointed at an album on the Home Screen whose
    /// photos the app has not rendered yet.
    var pendingAlbum: WidgetAlbumCatalog.Album?
}

struct PhotoWidgetProvider: AppIntentTimelineProvider {
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
        PhotoWidgetEntry(
            date: .now,
            kind: kind,
            settings: PhotoWidgetSettings.default(for: kind),
            image: nil,
            weather: nil,
            calendarSnapshot: nil
        )
    }

    func snapshot(
        for configuration: ConfigurePhotoWidgetIntent,
        in context: Context
    ) async -> PhotoWidgetEntry {
        let payload = Payload()
        return entry(for: .now, configuration: configuration, payload: payload)
    }

    func timeline(
        for configuration: ConfigurePhotoWidgetIntent,
        in context: Context
    ) async -> Timeline<PhotoWidgetEntry> {
        let calendar = Calendar.current
        let start = calendar.date(bySetting: .second, value: 0, of: .now) ?? .now
        // One pass over the files for the whole timeline, and one decode per
        // distinct picture in it. Reading them per entry would decode the same
        // JPEG sixty times to draw sixty different minutes of the same photo.
        let payload = Payload()
        let resolved = payload.resolve(kind: kind, configuration: configuration)
        // An album chosen on the Home Screen has no pictures until the app has
        // rendered them, so the ask is left where the app will find it.
        if let pending = resolved.pendingAlbum {
            PhotoWidgetFrameRequests.request(
                albumId: pending.id,
                title: pending.title,
                source: resolved.pendingSourceKind == .photo ? .photo : .album
            )
        }

        let showsClock = resolved.settings.showsTime
        let count = showsClock ? Self.clockEntries : Self.quietEntries
        let step = showsClock ? 1 : Self.quietStep

        let entries = (0..<count).compactMap { index -> PhotoWidgetEntry? in
            guard let date = calendar.date(byAdding: .minute, value: index * step, to: start)
            else { return nil }
            return entry(for: date, configuration: configuration, payload: payload, resolved: resolved)
        }
        let end = entries.last?.date ?? .now
        // A widget waiting on the app checks back sooner: the pictures arrive
        // the moment ShotDex is next opened, and the app reloads it then, but
        // this keeps a missed reload from lasting an hour.
        let policy: TimelineReloadPolicy = resolved.pendingAlbum == nil
            ? .after(end)
            : .after(calendar.date(byAdding: .minute, value: 15, to: start) ?? end)
        return Timeline(entries: entries, policy: policy)
    }

    /// Everything read off disk once per timeline build, with the pictures
    /// decoded lazily and kept.
    private final class Payload {
        let settings = PhotoWidgetSettingsFile.read()
        let weather = WeatherSnapshot.read()
        let calendarSnapshot = CalendarSnapshot.read()
        private var images: [String: Image] = [:]
        private var snapshots: [String: PhotoWidgetSnapshot] = [:]

        func resolve(
            kind: PhotoWidgetKind,
            configuration: ConfigurePhotoWidgetIntent
        ) -> PhotoWidgetResolvedConfiguration {
            PhotoWidgetResolvedConfiguration.resolve(
                kind: kind,
                settings: settings[kind],
                photoId: configuration.photo?.id,
                photoLabel: configuration.photo?.label,
                albumId: configuration.album?.id,
                albumTitle: configuration.album?.title,
                rotation: configuration.rotation.rotation,
                dimming: configuration.dimming.dimming,
                frameCount: { directory in self.snapshot(named: directory).frames.count }
            )
        }

        func image(
            directoryName: String,
            at date: Date,
            rotation: PhotoWidgetSettings.Rotation
        ) -> Image? {
            let snapshot = snapshot(named: directoryName)
            guard let index = PhotoWidgetSnapshot.frameIndex(
                at: date, count: snapshot.frames.count, rotation: rotation
            ) else { return nil }
            let key = "\(directoryName)-\(index)"
            if let cached = images[key] { return cached }
            guard let url = snapshot.imageURL(at: index, directoryName: directoryName),
                  let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data)
            else { return nil }
            let image = Image(uiImage: uiImage)
            images[key] = image
            return image
        }

        func snapshot(named directoryName: String) -> PhotoWidgetSnapshot {
            if let cached = snapshots[directoryName] { return cached }
            let snapshot = PhotoWidgetSnapshot.read(directoryName: directoryName)
            snapshots[directoryName] = snapshot
            return snapshot
        }
    }

    private func entry(
        for date: Date,
        configuration: ConfigurePhotoWidgetIntent,
        payload: Payload,
        resolved: PhotoWidgetResolvedConfiguration? = nil
    ) -> PhotoWidgetEntry {
        let resolved = resolved ?? payload.resolve(kind: kind, configuration: configuration)
        return PhotoWidgetEntry(
            date: date,
            kind: kind,
            settings: resolved.settings,
            image: payload.image(
                directoryName: resolved.frameDirectoryName,
                at: date,
                rotation: resolved.settings.rotation
            ),
            weather: payload.weather,
            calendarSnapshot: payload.calendarSnapshot,
            pendingAlbum: resolved.pendingAlbum
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
        AppIntentConfiguration(
            kind: kind.widgetKind,
            intent: ConfigurePhotoWidgetIntent.self,
            provider: PhotoWidgetProvider(kind: kind)
        ) { entry in
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
        case .clock: "The time over a photo or album you choose, in the style you set in ShotDex."
        case .calendar: "The month, or what is on today, over a photo or album you choose."
        case .weather: "The weather where you are, over a photo or album you choose."
        case .combined: "The time, the day and the weather, over a photo or album you choose."
        }
    }
}

struct PhotoWidgetBackground: View {
    let entry: PhotoWidgetEntry

    var body: some View {
        ZStack {
            if let image = entry.image {
                PhotoWidgetImageLayer(image: image, settings: entry.settings)
            } else {
                Color.black
            }
            if entry.settings.photoDimming > 0 {
                Color.black.opacity(entry.settings.photoDimming)
            }
            if entry.settings.legibility == .scrim {
                PhotoWidgetScrim(anchor: entry.settings.anchor)
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
                ZStack {
                    PhotoWidgetPositionedFace(
                        entry: entry,
                        size: proxy.size,
                        isCompact: family == .systemSmall
                    )
                    if let pending = entry.pendingAlbum {
                        // The album was chosen here on the Home Screen, so the
                        // app has not had a chance to copy its photos yet. Say
                        // so rather than showing black and looking broken.
                        PhotoWidgetPendingBanner(albumTitle: pending.title)
                    }
                }
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

/// The face, placed where the user dragged it.
///
/// Measuring the block before offsetting it is what keeps a block dragged
/// towards an edge inside the widget: the anchor says which fraction of the
/// free space it sits at, and the free space is the widget less the block.
struct PhotoWidgetPositionedFace: View {
    let entry: PhotoWidgetEntry
    let size: CGSize
    let isCompact: Bool

    @State private var contentSize: CGSize = .zero

    /// The margin the text keeps from the widget's own edges.
    private static let inset: CGFloat = 4

    var body: some View {
        PhotoWidgetFace(
            date: entry.date,
            settings: entry.settings,
            kind: entry.kind,
            width: size.width,
            weather: entry.weather,
            calendarSnapshot: entry.calendarSnapshot,
            isCompact: isCompact
        )
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { contentSize = proxy.size }
            }
        }
        .padding(Self.inset)
        .offset(
            entry.settings.anchor.offset(
                in: size, contentSize: contentSize, inset: Self.inset
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: entry.settings.anchor.alignment
        )
    }
}

/// Shown while an album picked in "Edit Widget" is waiting for the app to copy
/// its photos across.
struct PhotoWidgetPendingBanner: View {
    let albumTitle: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "photo.badge.arrow.down")
            Text(albumTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("Open ShotDex to copy these photos")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
