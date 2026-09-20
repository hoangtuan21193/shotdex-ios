import Foundation

/// The albums a widget may be pointed at, as a list the widget can read.
///
/// The Home Screen's own "Edit Widget" menu builds its album picker from an
/// `EntityQuery`, and that query runs inside the widget extension — which is
/// not allowed to touch PhotoKit here. So the app writes the list: an
/// identifier, a name and a count per album, and nothing else.
struct WidgetAlbumCatalog: Codable, Equatable {
    struct Album: Codable, Equatable, Identifiable, Hashable {
        /// `PHAssetCollection.localIdentifier`.
        var id: String
        var title: String
        var count: Int
    }

    var albums: [Album]
    var generatedAt: Date

    static let fileName = "album-catalog.json"
    /// Enough to cover a real library's albums without turning the picker into
    /// a scroll marathon or the file into something worth paging.
    static let maximumAlbums = 200

    static let empty = WidgetAlbumCatalog(albums: [], generatedAt: .distantPast)

    static func read() -> WidgetAlbumCatalog {
        guard let url = WidgetSharedContainer.url?.appendingPathComponent(fileName)
        else { return .empty }
        return WidgetSharedContainer.decode(WidgetAlbumCatalog.self, at: url) ?? .empty
    }

    func album(id: String) -> Album? { albums.first { $0.id == id } }

    /// The albums whose name contains `text`, for the picker's search field.
    /// Case- and accent-insensitive, because "Đà Lạt" should be found by
    /// typing "da lat".
    func matching(_ text: String) -> [Album] {
        let query = Self.normalized(text)
        guard !query.isEmpty else { return albums }
        return albums.filter { Self.normalized($0.title).contains(query) }
    }

    /// Lowercased and stripped of accents. `đ` is spelled out because it is a
    /// letter of its own in Unicode, not a `d` with a mark, so folding leaves
    /// it alone — and a Vietnamese album name is the case this search is for.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
