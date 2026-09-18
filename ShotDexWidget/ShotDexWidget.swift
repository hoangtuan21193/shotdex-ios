import SwiftUI
import WidgetKit

/// Home and Lock Screen widgets for ShotDex.
///
/// They show the digest the app leaves in the shared container — how much of
/// the library there is, how much of it is this month, and the gear in front.
/// The widget never touches the photo library itself: an extension reading
/// PhotoKit would put photo metadata in a second process on a timeline refresh
/// schedule nobody asked for, and the app's promise is that it stays in one
/// place. It reads a file the app already wrote.
@main
struct ShotDexWidgetBundle: WidgetBundle {
    var body: some Widget {
        GearWidget()
    }
}

struct GearEntry: TimelineEntry {
    let date: Date
    let snapshot: GearSnapshot
    let cover: Data?
    /// True when the shared container could not be read at all — the widget
    /// then invites the user to open the app rather than showing zeroes as if
    /// they were real.
    let isUnavailable: Bool
}

struct GearProvider: TimelineProvider {
    func placeholder(in context: Context) -> GearEntry {
        GearEntry(
            date: .now,
            snapshot: GearSnapshot(
                totalPhotos: 12_480,
                photosThisMonth: 214,
                topCamera: "Canon EOS R6",
                topLens: "RF24-70mm F2.8 L IS USM",
                generatedAt: .now
            ),
            cover: nil,
            isUnavailable: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GearEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GearEntry>) -> Void) {
        // The digest only changes when the app indexes, so a slow cadence is
        // right; the app also reloads timelines itself after an index run.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> GearEntry {
        guard let snapshot = GearSnapshot.read() else {
            return GearEntry(
                date: .now,
                snapshot: .empty,
                cover: nil,
                isUnavailable: true
            )
        }
        return GearEntry(
            date: .now,
            snapshot: snapshot,
            cover: GearSnapshot.readCoverData(),
            isUnavailable: false
        )
    }
}

struct GearWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShotDexGear", provider: GearProvider()) { entry in
            GearWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your Gear")
        .description("How much you have shot, and what you shot it with.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
        ])
    }
}

struct GearWidgetView: View {
    let entry: GearEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            lockScreen
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ShotDex")
                .font(.caption2.weight(.semibold))
            Text(countLine)
                .font(.headline)
                .monospacedDigit()
            if let camera = entry.snapshot.topCamera {
                Text(camera).font(.caption2).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.isUnavailable {
                unavailable
            } else {
                Text("\(entry.snapshot.totalPhotos, format: .number)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("photos indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let camera = entry.snapshot.topCamera {
                    Text(camera)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            if let cover = entry.cover, let image = UIImage(data: cover) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                if entry.isUnavailable {
                    unavailable
                } else {
                    Text(countLine)
                        .font(.headline)
                        .monospacedDigit()
                    if let camera = entry.snapshot.topCamera {
                        Label(camera, systemImage: "camera")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    if let lens = entry.snapshot.topLens {
                        Label(lens, systemImage: "camera.aperture")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("\(entry.snapshot.photosThisMonth, format: .number) this month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open ShotDex")
                .font(.headline)
            Text("Index your library to see it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var countLine: String {
        "\(entry.snapshot.totalPhotos.formatted()) photos"
    }
}
