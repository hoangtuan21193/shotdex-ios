import SwiftUI
import WidgetKit

/// "On This Day": the photos this date holds in previous years.
///
/// It reads the day files the app leaves in the App Group and never the photo
/// library — the rule the Gear widget set (§7.4b) and for the same reason.
/// One entry per day, so the widget rolls over at local midnight instead of
/// showing yesterday's date over yesterday's photos.
struct OnThisDayEntry: TimelineEntry {
    let date: Date
    let snapshot: OnThisDaySnapshot?
    let images: [Image]
}

struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: .now, snapshot: nil, images: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        let calendar = Calendar.current
        let days = (0...OnThisDaySnapshot.daysAhead).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: .now))
        }
        // The first entry is "now" so an installed widget draws immediately;
        // the rest land on each following midnight, which is when the day the
        // widget is describing actually changes.
        var entries = [entry(for: .now)]
        entries.append(contentsOf: days.dropFirst().map { entry(for: $0) })
        // After the last precomputed day there is nothing left to show, so ask
        // to be rebuilt then: the app will have written more days if it has
        // been opened, and the invite state is honest if it has not.
        let end = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .now
        completion(Timeline(entries: entries, policy: .after(end)))
    }

    private func entry(for date: Date) -> OnThisDayEntry {
        let key = WidgetSharedContainer.dayKey(for: date)
        let snapshot = OnThisDaySnapshot.read(dayKey: key)
        let images = (snapshot?.photos.indices ?? (0..<0)).compactMap { index -> Image? in
            guard let url = snapshot?.imageURL(at: index),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data)
            else { return nil }
            return Image(uiImage: image)
        }
        return OnThisDayEntry(date: date, snapshot: snapshot, images: images)
    }
}

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: OnThisDaySnapshot.widgetKind,
            provider: OnThisDayProvider()
        ) { entry in
            OnThisDayWidgetView(entry: entry)
        }
        .configurationDisplayName("On This Day")
        .description("The photos you took on this date in past years.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
        ])
    }
}

struct OnThisDayWidgetView: View {
    let entry: OnThisDayEntry
    @Environment(\.widgetFamily) private var family

    private var hasPhotos: Bool { !entry.images.isEmpty }

    var body: some View {
        content
            // The small family is one photo edge to edge, so the photo is the
            // widget's background and the caption is the only content — that
            // is what keeps the caption inside the system's content margins
            // instead of being laid out against an overflowing image.
            .containerBackground(for: .widget) {
                if family == .systemSmall, let hero = entry.images.first {
                    fill(hero)
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .widgetURL(
                WidgetDeepLink.onThisDay(
                    dayKey: entry.snapshot?.dayKey ?? WidgetSharedContainer.dayKey(for: entry.date)
                ).url
            )
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            lockScreen
        case .systemLarge:
            large
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Families

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("On This Day")
                .font(.caption2.weight(.semibold))
            Text(countLine)
                .font(.headline)
                .monospacedDigit()
            Text(yearsLine)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        Group {
            if entry.images.first != nil {
                VStack(alignment: .leading, spacing: 1) {
                    Text(heroYearLine)
                        .font(.caption.weight(.semibold))
                    Text(countLine)
                        .font(.caption2)
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var medium: some View {
        HStack(spacing: 10) {
            if hasPhotos {
                ZStack(alignment: .bottomLeading) {
                    fill(entry.images[0])
                    captionScrim
                    Text(heroYearLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .frame(width: 118)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("On This Day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(dateLine)
                        .font(.headline)
                    Text(countLine)
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(yearsLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasPhotos {
                HStack(alignment: .firstTextBaseline) {
                    Text(dateLine)
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text(countLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                // One tile per year the day holds, biggest first: the point of
                // the widget is the span, not a single frame.
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        tile(at: 0)
                            .gridCellColumns(entry.images.count > 1 ? 2 : 3)
                        if entry.images.count > 1 {
                            tile(at: 1)
                        }
                    }
                    if entry.images.count > 2 {
                        GridRow {
                            tile(at: 2)
                            if entry.images.count > 3 {
                                tile(at: 3)
                                    .gridCellColumns(2)
                            } else {
                                Color.clear.gridCellColumns(2)
                            }
                        }
                    }
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Pieces

    private func tile(at index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            if entry.images.indices.contains(index) {
                fill(entry.images[index])
                captionScrim
                Text(yearLabel(at: index))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// A photo filling its slot. The explicit frame and the clip are the
    /// point: a `scaledToFill` image is larger than the space it is given, and
    /// a stack sized by it lays its other children out against the overflow —
    /// which put the caption off the left edge of the widget.
    private func fill(_ image: Image) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }

    /// Enough gradient under a caption to read it on a bright photo, and no
    /// more: the picture is the content.
    private var captionScrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.55), .clear],
            startPoint: .bottom,
            endPoint: .center
        )
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing on this day")
                .font(.headline)
            Text("Open ShotDex so it can look through your library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Copy

    private var dateLine: String {
        entry.date.formatted(.dateTime.day().month(.wide))
    }

    private var countLine: String {
        let count = entry.snapshot?.photoCount ?? 0
        return count == 1 ? "1 photo" : "\(count.formatted()) photos"
    }

    private var yearsLine: String {
        guard let years = entry.snapshot?.years, !years.isEmpty else { return "No past years yet" }
        return years.prefix(4).map(String.init).joined(separator: " · ")
    }

    private var heroYearLine: String { yearLabel(at: 0) }

    private func yearLabel(at index: Int) -> String {
        guard let photo = entry.snapshot?.photos[safe: index] else { return "" }
        let yearsAgo = Calendar.current.component(.year, from: entry.date) - photo.year
        if yearsAgo <= 0 { return String(photo.year) }
        return yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
