import Foundation
import Photos
import WidgetKit

/// Publishes the album list the Home Screen's "Edit Widget" menu picks from.
///
/// The menu's picker is answered by an `EntityQuery` running inside the widget
/// extension, and that extension does not read PhotoKit here. So the app hands
/// it a list: identifier, name, count. Nothing about any photo goes with it.
@MainActor
struct WidgetAlbumCatalogWriter {
    /// Rewritten when the library's albums change or the list is a day old;
    /// the fetch is cheap but not free, and it runs on every foreground.
    private static let staleAfter: TimeInterval = 24 * 3600

    func write(now: Date = .now, force: Bool = false) async {
        guard let container = WidgetSharedContainer.url else { return }
        let existing = WidgetAlbumCatalog.read()
        let albums = await Task.detached(priority: .utility) { Self.albums() }.value
        guard force
            || albums.map(\.id) != existing.albums.map(\.id)
            || albums != existing.albums
            || now.timeIntervalSince(existing.generatedAt) > Self.staleAfter
        else { return }

        try? WidgetSharedContainer.encode(
            WidgetAlbumCatalog(albums: albums, generatedAt: now),
            to: container.appendingPathComponent(WidgetAlbumCatalog.fileName)
        )
    }

    /// User albums first, then the system ones worth pointing a widget at.
    /// Empty albums are left out: an album with nothing in it draws nothing.
    private nonisolated static func albums() -> [WidgetAlbumCatalog.Album] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d", PHAssetMediaType.image.rawValue
        )

        var albums: [WidgetAlbumCatalog.Album] = []

        func append(_ collection: PHAssetCollection) {
            let count = PHAsset.fetchAssets(in: collection, options: options).count
            guard count > 0 else { return }
            albums.append(
                WidgetAlbumCatalog.Album(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Album",
                    count: count
                )
            )
        }

        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            .enumerateObjects { collection, _, _ in append(collection) }

        // The two system albums a photographer actually points something at.
        for subtype in [PHAssetCollectionSubtype.smartAlbumFavorites, .smartAlbumRecentlyAdded] {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in append(collection) }
        }

        return Array(albums.prefix(WidgetAlbumCatalog.maximumAlbums))
    }
}
