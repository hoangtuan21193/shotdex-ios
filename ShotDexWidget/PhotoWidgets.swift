import AppIntents
import SwiftUI
import WidgetKit

/// The one widget that draws over a photo the user chose.
///
/// Which design it wears is answered in the Home Screen's own Edit Widget
/// menu, so two of them can sit side by side looking nothing alike. The
/// settings file says what each design draws, and everything it draws — the
/// picture, the events, the weather — was written into the App Group by the
/// app. The extension reads files and nothing else. No PhotoKit, no EventKit,
/// no network, no location.
struct PhotoWidgetEntry: TimelineEntry {
    let date: Date
    /// The design this placed widget wears, so the view can name it when
    /// there is nothing else to show.
    let designName: String
    let settings: PhotoWidgetSettings
    let image: Image?
    let weather: WeatherSnapshot?
    let calendarSnapshot: CalendarSnapshot?
    /// Set when this widget was pointed at an album on the Home Screen whose
    /// photos the app has not rendered yet.
    var pendingAlbum: WidgetAlbumCatalog.Album?
    /// Width ÷ height of the picture, so a two-finger drag can reach the part
    /// the fill cropped away.
    var imageAspectRatio: Double = 1
    /// How bright that picture is, cell by cell. Measured once when it is
    /// decoded and carried with it, because the Smart colour asks a different
    /// question of it for every block of text.
    var lumaGrid: PhotoWidgetLumaGrid?
}

struct PhotoWidgetProvider: AppIntentTimelineProvider {
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
            designName: "",
            settings: PhotoWidgetSettings(),
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
        let prepared = payload.resolve(configuration: configuration)
        let (settings, resolved) = (prepared.settings, prepared.resolved)
        // A source chosen on the Home Screen has no pictures until the app has
        // rendered them, so the ask is left where the app will find it.
        if let pending = resolved.pendingSource {
            PhotoWidgetFrameRequests.request(
                albumId: pending.id,
                title: pending.title,
                source: pending.kind == .photo ? .photo : .album
            )
        }

        let showsClock = settings.showsTime
        let count = showsClock ? Self.clockEntries : Self.quietEntries
        let step = showsClock ? 1 : Self.quietStep

        let entries = (0..<count).compactMap { index -> PhotoWidgetEntry? in
            guard let date = calendar.date(byAdding: .minute, value: index * step, to: start)
            else { return nil }
            return entry(
                for: date,
                configuration: configuration,
                payload: payload,
                prepared: prepared
            )
        }
        let end = entries.last?.date ?? .now
        // A widget waiting on the app checks back sooner: the pictures arrive
        // the moment ShotDex is next opened, and the app reloads it then, but
        // this keeps a missed reload from lasting an hour.
        let policy: TimelineReloadPolicy = resolved.pendingSource == nil
            ? .after(end)
            : .after(calendar.date(byAdding: .minute, value: 15, to: start) ?? end)
        return Timeline(entries: entries, policy: policy)
    }

    /// Everything read off disk once per timeline build, with the pictures
    /// decoded lazily and kept.
    private final class Payload {
        var settings = PhotoWidgetSettingsFile.read()
        let weather = WeatherSnapshot.read()
        let calendarSnapshot = CalendarSnapshot.read()
        private var images: [String: LoadedImage] = [:]
        private var snapshots: [String: PhotoWidgetSnapshot] = [:]

        /// Folds the Home Screen menu's answer into the shared settings — once
        /// per change — then says where this widget's pictures live.
        func resolve(
            configuration: ConfigurePhotoWidgetIntent
        ) -> (
            design: PhotoWidgetDesign,
            settings: PhotoWidgetSettings,
            resolved: PhotoWidgetResolvedConfiguration
        ) {
            // A widget placed before it was configured, or one whose design
            // the user deleted, falls back to the first design rather than
            // drawing nothing.
            let design = self.settings.design(id: configuration.design?.id)
            var settings = design.settings
            let signature = PhotoWidgetIntentApplication.signature(
                photoId: configuration.photo?.id,
                albumId: configuration.album?.id,
                rotationRawValue: configuration.rotation.rotation?.rawValue,
                dimming: configuration.dimming.dimming
            )
            let changed = PhotoWidgetIntentApplication.apply(
                to: &settings,
                photoId: configuration.photo?.id,
                photoLabel: configuration.photo?.label,
                albumId: configuration.album?.id,
                albumTitle: configuration.album?.title,
                rotation: configuration.rotation.rotation,
                dimming: configuration.dimming.dimming,
                signature: signature
            )
            if changed {
                // Written back so ShotDex's own Settings screen shows what was
                // chosen out here, and its preview matches the widget.
                var file = self.settings
                file[design.id] = settings
                file.write()
                self.settings = file
            }
            let resolved = PhotoWidgetResolvedConfiguration.resolve(
                designId: design.id,
                source: settings.source,
                snapshot: { self.snapshot(named: $0) }
            )
            return (design, settings, resolved)
        }

        struct LoadedImage {
            let image: Image
            let aspectRatio: Double
            let lumaGrid: PhotoWidgetLumaGrid?
        }

        func image(
            directoryName: String,
            at date: Date,
            rotation: PhotoWidgetSettings.Rotation,
            measuresLuma: Bool
        ) -> LoadedImage? {
            let snapshot = snapshot(named: directoryName)
            guard let index = PhotoWidgetSnapshot.frameIndex(
                at: date, count: snapshot.frames.count, rotation: rotation
            ) else { return nil }
            let key = "\(directoryName)-\(index)-\(measuresLuma)"
            if let cached = images[key] { return cached }
            guard let url = snapshot.imageURL(at: index, directoryName: directoryName),
                  let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data)
            else { return nil }
            let aspect = uiImage.size.height > 0
                ? Double(uiImage.size.width / uiImage.size.height)
                : 1
            let loaded = LoadedImage(
                image: Image(uiImage: uiImage),
                aspectRatio: aspect,
                // Only when the user asked for it: one 16×16 draw is cheap,
                // but a widget extension pays for every pass it does not need,
                // and a fixed swatch never asks this question.
                lumaGrid: measuresLuma
                    ? uiImage.cgImage.flatMap(PhotoWidgetLumaGrid.make(from:))
                    : nil
            )
            images[key] = loaded
            return loaded
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
        prepared: (
            design: PhotoWidgetDesign,
            settings: PhotoWidgetSettings,
            resolved: PhotoWidgetResolvedConfiguration
        )? = nil
    ) -> PhotoWidgetEntry {
        let prepared = prepared ?? payload.resolve(configuration: configuration)
        let loaded = payload.image(
            directoryName: prepared.resolved.frameDirectoryName,
            at: date,
            rotation: prepared.settings.rotation,
            measuresLuma: WidgetTextColor.isSmart(hex: prepared.settings.textColorHex)
        )
        return PhotoWidgetEntry(
            date: date,
            designName: prepared.design.name,
            settings: prepared.settings,
            image: loaded?.image,
            weather: payload.weather,
            calendarSnapshot: payload.calendarSnapshot,
            pendingAlbum: prepared.resolved.pendingSource.map {
                WidgetAlbumCatalog.Album(id: $0.id, title: $0.title, count: 0)
            },
            imageAspectRatio: loaded?.aspectRatio ?? 1,
            lumaGrid: loaded?.lumaGrid
        )
    }
}

/// The one photo widget. Which design it wears is a per-instance answer given
/// in the Home Screen's Edit Widget menu, so two of them can look nothing
/// alike — which is the thing four fixed kinds could never do.
struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: PhotoWidgetIdentity.widgetKind,
            intent: ConfigurePhotoWidgetIntent.self,
            provider: PhotoWidgetProvider()
        ) { entry in
            // The background is chosen inside the view, where the family is
            // known: a Lock Screen accessory has no photo behind it, and
            // painting one there would show as a grey block.
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("Photo Widget")
        .description(
            "The time, the date, the month, today's events or the weather — over a photo or album you choose. Pick which of your designs this one wears."
        )
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
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
        PhotoWidgetArrangedFace(
            date: entry.date,
            settings: entry.settings,
            size: size,
            weather: entry.weather,
            calendarSnapshot: entry.calendarSnapshot,
            isCompact: isCompact,
            lumaGrid: entry.lumaGrid,
            imageAspectRatio: entry.imageAspectRatio
        ) { _, _ in EmptyView() }
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
