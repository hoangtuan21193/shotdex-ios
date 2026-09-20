import Foundation
import Photos
import UIKit

/// Publishes the short list of recent photos the Home Screen's widget menu
/// offers one by one, with a thumbnail for each row.
///
/// AppIntents has no photo picker — a configuration menu can only list
/// entities — so this is how "choose a photo" works out there. It is a list of
/// what was shot lately rather than the whole library: a menu is not a grid,
/// and a hundred rows is already a long scroll.
@MainActor
struct WidgetPhotoCatalogWriter {
    let photoLibrary: PhotoLibraryService

    /// Rewritten when the newest photo changes or the list is half a day old.
    private static let staleAfter: TimeInterval = 12 * 3600

    func write(now: Date = .now, force: Bool = false) async {
        guard let container = WidgetSharedContainer.url else { return }
        let directory = WidgetPhotoCatalog.directoryURL(in: container)
        let existing = WidgetPhotoCatalog.read()
        let assets = Self.recentAssets()
        guard !assets.isEmpty else { return }

        let newestId = assets.first?.localIdentifier
        guard force
            || existing.photos.first?.id != newestId
            || now.timeIntervalSince(existing.generatedAt) > Self.staleAfter
        else { return }

        let renderer = WidgetImageRenderer(photoLibrary: photoLibrary)
        var photos: [WidgetPhotoCatalog.Photo] = []
        for (index, asset) in assets.enumerated() {
            let fileName = "thumb-\(index).jpg"
            guard await renderer.writeThumbnail(
                for: asset,
                to: directory.appendingPathComponent(fileName),
                maxPixels: WidgetPhotoCatalog.thumbnailPixels
            ) else { continue }
            photos.append(
                WidgetPhotoCatalog.Photo(
                    id: asset.localIdentifier,
                    label: Self.label(for: asset),
                    thumbnailFileName: fileName
                )
            )
        }
        guard !photos.isEmpty else { return }

        try? WidgetSharedContainer.encode(
            WidgetPhotoCatalog(photos: photos, generatedAt: now),
            to: directory.appendingPathComponent(WidgetPhotoCatalog.fileName)
        )
        WidgetImageRenderer.prune(
            directory: directory,
            keeping: Set(photos.map(\.thumbnailFileName) + [WidgetPhotoCatalog.fileName])
        )
    }

    private nonisolated static func recentAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d", PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = WidgetPhotoCatalog.maximumPhotos
        let fetch = PHAsset.fetchAssets(with: options)
        return (0..<fetch.count).map { fetch.object(at: $0) }
    }

    /// The date, and the time with it — a day with a dozen frames would
    /// otherwise be a dozen identical rows.
    private nonisolated static func label(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Photo" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
