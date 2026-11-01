import Foundation

/// How an album's photos are ordered on screen.
///
/// `albumOrder` is the album's own arrangement — the order photos were added,
/// or the order the user dragged them into in Photos. PhotoKit gives it by
/// asking for no sort at all, which is why it is not just another descriptor.
enum AlbumSortOrder: String, CaseIterable, Identifiable, Sendable {
    case albumOrder
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albumOrder: "Album Order"
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }

    var systemImage: String {
        switch self {
        case .albumOrder: "list.number"
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }

    var sortDescriptors: [NSSortDescriptor]? {
        switch self {
        case .albumOrder: nil
        case .newestFirst: [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .oldestFirst: [NSSortDescriptor(key: "creationDate", ascending: true)]
        }
    }

    /// The same order expressed for the index, for albums whose photos come
    /// from the database rather than from PhotoKit. "Album Order" has no
    /// meaning there — a query has no arrangement of its own — so it reads as
    /// newest first, which is what the album offers in its place.
    var librarySort: SortOption {
        switch self {
        case .oldestFirst: .dateTakenOldest
        case .albumOrder, .newestFirst: .dateTakenNewest
        }
    }
}

/// Remembers the order each album was last browsed in.
///
/// Per album, not one setting for all of them: a trip album reads in the order
/// it happened, a wallpapers album in the order things were added, and one
/// global switch would make the user re-pick every time they moved between the
/// two.
enum AlbumSortStore {
    private static let key = "albums.sortOrder"

    static func order(for albumId: String, isSmartAlbum: Bool) -> AlbumSortOrder {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        if let raw = stored?[albumId], let order = AlbumSortOrder(rawValue: raw) {
            return order
        }
        // A smart album has no arrangement of its own to fall back on.
        return isSmartAlbum ? .newestFirst : .albumOrder
    }

    static func setOrder(_ order: AlbumSortOrder, for albumId: String) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[albumId] = order.rawValue
        UserDefaults.standard.set(stored, forKey: key)
    }
}
