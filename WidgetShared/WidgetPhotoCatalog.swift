import Foundation

/// The photos the Home Screen's widget menu can offer one by one.
///
/// AppIntents has no photo picker: a configuration menu can only list
/// entities. So the app publishes a short list of recent photos — an
/// identifier, a label and a thumbnail small enough to sit in a menu row — and
/// the picker draws that. It is a list of what the user shot lately, not their
/// whole library, because a menu is not a photo grid.
struct WidgetPhotoCatalog: Codable, Equatable {
    struct Photo: Codable, Equatable, Identifiable, Hashable {
        /// `PHAsset.localIdentifier`.
        var id: String
        /// What the row reads: the date, and the time for a day with several.
        var label: String
        /// File inside `directoryName`.
        var thumbnailFileName: String
    }

    var photos: [Photo]
    var generatedAt: Date

    static let fileName = "photo-catalog.json"
    static let directoryName = "widget-photo-catalog"
    /// How many recent photos the menu offers. A hundred covers "the one I
    /// took this week" — the case this list is for — and costs about a
    /// megabyte of thumbnails.
    static let maximumPhotos = 100
    /// Longest edge of a menu thumbnail, in pixels.
    static let thumbnailPixels: CGFloat = 180

    static let empty = WidgetPhotoCatalog(photos: [], generatedAt: .distantPast)

    static func directoryURL(in container: URL) -> URL {
        container.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func read() -> WidgetPhotoCatalog {
        guard let container = WidgetSharedContainer.url else { return .empty }
        return WidgetSharedContainer.decode(
            WidgetPhotoCatalog.self,
            at: directoryURL(in: container).appendingPathComponent(fileName)
        ) ?? .empty
    }

    func photo(id: String) -> Photo? { photos.first { $0.id == id } }

    func thumbnailData(for photo: Photo) -> Data? {
        guard let container = WidgetSharedContainer.url else { return nil }
        return try? Data(
            contentsOf: Self.directoryURL(in: container)
                .appendingPathComponent(photo.thumbnailFileName)
        )
    }

    /// Rows whose label contains `text` — the date, in practice, since that is
    /// all a photo row says. Same accent-blind matching as the album list.
    func matching(_ text: String) -> [Photo] {
        let query = WidgetAlbumCatalog.normalized(text)
        guard !query.isEmpty else { return photos }
        return photos.filter { WidgetAlbumCatalog.normalized($0.label).contains(query) }
    }
}
