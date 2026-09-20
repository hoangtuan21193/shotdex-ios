import Foundation
import Photos
import WidgetKit

/// Renders the photo (or the album's photos) behind the Clock widget.
///
/// Same rule as the other two widgets: the extension never touches PhotoKit,
/// so whatever it shows has to be sitting in the App Group before it asks.
/// A single-photo source writes one file; an album writes up to
/// `ClockWidgetSnapshot.maxFrames`, and the widget picks one by the clock.
@MainActor
struct ClockWidgetSnapshotWriter {
    let photoLibrary: PhotoLibraryService

    func write(settings: ClockWidgetSettings) async {
        guard let container = WidgetSharedContainer.url else { return }
        let directory = ClockWidgetSnapshot.directoryURL(in: container)
        let assets = Self.assets(for: settings.source)

        let renderer = WidgetImageRenderer(photoLibrary: photoLibrary)
        var frames: [ClockWidgetSnapshot.Frame] = []
        for (index, asset) in assets.enumerated() {
            let fileName = "frame-\(index).jpg"
            // The user chose this picture on purpose, so an iCloud-only
            // original is worth a download here — unlike the On This Day
            // frames, which are picked for them.
            guard await renderer.write(
                asset: asset,
                to: directory.appendingPathComponent(fileName),
                allowNetwork: true
            ) else { continue }
            frames.append(
                ClockWidgetSnapshot.Frame(assetId: asset.localIdentifier, fileName: fileName)
            )
        }

        let snapshot = ClockWidgetSnapshot(frames: frames, generatedAt: .now)
        try? WidgetSharedContainer.encode(
            snapshot,
            to: directory.appendingPathComponent(ClockWidgetSnapshot.fileName)
        )
        WidgetImageRenderer.prune(
            directory: directory,
            keeping: Set(frames.map(\.fileName) + [ClockWidgetSnapshot.fileName])
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ClockWidgetSettings.widgetKind)
    }

    /// The assets a source resolves to, newest first, capped at the number of
    /// frames kept on disk.
    private static func assets(for source: ClockWidgetSettings.Source) -> [PHAsset] {
        switch source {
        case .none:
            return []
        case .photo(let assetId):
            return PhotoLibraryService.fetchAssets(ids: [assetId])
        case .album(let collectionId, _):
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [collectionId], options: nil
            )
            guard let collection = collections.firstObject else { return [] }
            let options = PHFetchOptions()
            // Stills only: a widget cannot play a video, and a poster frame of
            // one is a picture the user did not choose.
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetch = PHAsset.fetchAssets(in: collection, options: options)
            let upperBound = min(fetch.count, ClockWidgetSnapshot.maxFrames)
            return (0..<upperBound).map { fetch.object(at: $0) }
        }
    }
}
