import Foundation

/// What the app leaves behind for the On This Day widget: one file per
/// calendar day, holding the day's count, the years it spans and a few
/// small JPEGs.
///
/// The widget never touches PhotoKit (see the widget bundle's note), so it
/// cannot work out "this day in past years" itself. The app precomputes a
/// few days at launch and on becoming active, and the widget's timeline
/// steps from one day's file to the next at each local midnight. A day with
/// no file — the app has not been opened for a few days — shows an invite
/// to open it rather than stale photos labelled with the wrong date.
struct OnThisDaySnapshot: Codable, Equatable {
    struct Photo: Codable, Equatable, Identifiable {
        var assetId: String
        var year: Int
        /// File name inside `directoryName`.
        var fileName: String
        var id: String { assetId }
    }

    /// `WidgetSharedContainer.dayKey` of the day this describes.
    var dayKey: String
    /// Every matching photo and video, not just the ones with a file.
    var photoCount: Int
    /// Distinct capture years, newest first.
    var years: [Int]
    /// Up to `maxPhotos`, in display order (the hero first).
    var photos: [Photo]
    var generatedAt: Date
    /// What the photo library looked like when this was written — how many
    /// browsable items it held and when the newest one was taken. The app
    /// rewrites the day files when this stops matching, so a photo imported
    /// this morning appears in the widget on the next foreground rather than
    /// whenever the staleness timer happens to expire. Optional so a file
    /// written before the field existed still decodes.
    var libraryStamp: String?

    static let directoryName = "on-this-day"
    static let maxPhotos = 4
    /// Today plus this many following days are written on each refresh. Each
    /// day costs one compound OR-predicate fetch over the whole library, so
    /// this is deliberately short: enough that the widget survives a couple of
    /// midnights without the app being opened, not a week of pre-rendering.
    static let daysAhead = 2
    static let widgetKind = "ShotDexOnThisDay"

    static func directoryURL(in container: URL) -> URL {
        container.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileName(dayKey: String) -> String { "\(dayKey).json" }

    static func imageFileName(dayKey: String, index: Int) -> String { "\(dayKey)-\(index).jpg" }

    static func read(dayKey: String) -> OnThisDaySnapshot? {
        guard let container = WidgetSharedContainer.url else { return nil }
        return WidgetSharedContainer.decode(
            OnThisDaySnapshot.self,
            at: directoryURL(in: container).appendingPathComponent(fileName(dayKey: dayKey))
        )
    }

    func imageURL(at index: Int) -> URL? {
        guard photos.indices.contains(index), let container = WidgetSharedContainer.url else { return nil }
        return Self.directoryURL(in: container).appendingPathComponent(photos[index].fileName)
    }

    /// The date this snapshot is for, at local midnight.
    func date(calendar: Calendar = .current) -> Date? {
        WidgetSharedContainer.date(fromDayKey: dayKey, calendar: calendar)
    }

    /// Which of a day's photos make the cut, given each candidate's capture
    /// year in display order (newest first).
    ///
    /// One from every year first, so a day that spans five years shows five
    /// years rather than four frames from the same afternoon; then the
    /// remaining slots fill in order. Pure, so it is unit-tested.
    static func featuredIndices(years: [Int], limit: Int = maxPhotos) -> [Int] {
        guard limit > 0 else { return [] }
        var chosen: [Int] = []
        var seenYears: Set<Int> = []
        for (index, year) in years.enumerated() where seenYears.insert(year).inserted {
            chosen.append(index)
            if chosen.count == limit { return chosen }
        }
        for index in years.indices where !chosen.contains(index) {
            chosen.append(index)
            if chosen.count == limit { break }
        }
        return chosen
    }
}
