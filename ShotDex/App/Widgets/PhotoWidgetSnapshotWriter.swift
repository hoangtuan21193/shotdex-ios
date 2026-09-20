import Foundation
import Photos
import WidgetKit

/// Renders the photo (or the album's photos) behind one photo widget.
///
/// Same rule as every other widget payload: the extension never touches
/// PhotoKit, so whatever it shows has to be sitting in the App Group before it
/// asks. A single-photo source writes one file; an album writes up to
/// `PhotoWidgetSnapshot.maxFrames`, and the widget picks one by the clock.
@MainActor
struct PhotoWidgetSnapshotWriter {
    let photoLibrary: PhotoLibraryService

    func write(kind: PhotoWidgetKind, settings: PhotoWidgetSettings) async {
        guard let container = WidgetSharedContainer.url else { return }
        let directory = PhotoWidgetSnapshot.directoryURL(for: kind, in: container)
        let assets = Self.assets(for: settings.source)

        let renderer = WidgetImageRenderer(photoLibrary: photoLibrary)
        var frames: [PhotoWidgetSnapshot.Frame] = []
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
                PhotoWidgetSnapshot.Frame(assetId: asset.localIdentifier, fileName: fileName)
            )
        }

        let snapshot = PhotoWidgetSnapshot(frames: frames, generatedAt: .now)
        try? WidgetSharedContainer.encode(
            snapshot,
            to: directory.appendingPathComponent(PhotoWidgetSnapshot.fileName)
        )
        WidgetImageRenderer.prune(
            directory: directory,
            keeping: Set(frames.map(\.fileName) + [PhotoWidgetSnapshot.fileName])
        )
        WidgetCenter.shared.reloadTimelines(ofKind: kind.widgetKind)
    }

    /// Renders the albums that widgets asked for from the Home Screen.
    ///
    /// The widget can point itself at an album but cannot copy its photos, so
    /// it leaves the ask in the App Group and shows "Open ShotDex" until this
    /// runs. Each album's frames live in a folder of their own, keyed by the
    /// album, so two widgets on the same album share one copy.
    @discardableResult
    func fulfilRequests(now: Date = .now) async -> Int {
        guard let container = WidgetSharedContainer.url else { return 0 }
        let requests = PhotoWidgetFrameRequests.read().requests
        guard !requests.isEmpty else { return 0 }

        var fulfilled: Set<String> = []
        for request in requests {
            let directoryName = PhotoWidgetSnapshot.albumDirectoryName(albumId: request.albumId)
            let directory = PhotoWidgetSnapshot.directoryURL(named: directoryName, in: container)
            let assets = Self.assets(
                for: .album(collectionId: request.albumId, title: request.title)
            )
            // An album that no longer exists still counts as answered: leaving
            // the ask queued would have the widget re-request it for ever.
            guard !assets.isEmpty else {
                fulfilled.insert(request.albumId)
                continue
            }
            await write(assets: assets, to: directory)
            fulfilled.insert(request.albumId)
        }

        PhotoWidgetFrameRequests.clear(albumIds: fulfilled)
        Self.pruneAlbumFolders(in: container, keeping: fulfilled)
        for kind in PhotoWidgetKind.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.widgetKind)
        }
        return fulfilled.count
    }

    /// Renders a set of assets into one folder and writes its snapshot.
    private func write(assets: [PHAsset], to directory: URL) async {
        let renderer = WidgetImageRenderer(photoLibrary: photoLibrary)
        var frames: [PhotoWidgetSnapshot.Frame] = []
        for (index, asset) in assets.enumerated() {
            let fileName = "frame-\(index).jpg"
            guard await renderer.write(
                asset: asset,
                to: directory.appendingPathComponent(fileName),
                allowNetwork: true
            ) else { continue }
            frames.append(
                PhotoWidgetSnapshot.Frame(assetId: asset.localIdentifier, fileName: fileName)
            )
        }
        try? WidgetSharedContainer.encode(
            PhotoWidgetSnapshot(frames: frames, generatedAt: .now),
            to: directory.appendingPathComponent(PhotoWidgetSnapshot.fileName)
        )
        WidgetImageRenderer.prune(
            directory: directory,
            keeping: Set(frames.map(\.fileName) + [PhotoWidgetSnapshot.fileName])
        )
    }

    /// Album folders are per album, not per widget, so nothing removes them
    /// when a widget is deleted. Keep the ones just rendered and the few most
    /// recently written; the rest were pointed at by widgets that are gone.
    private static func pruneAlbumFolders(in container: URL, keeping albumIds: Set<String>) {
        let manager = FileManager.default
        let keep = Set(albumIds.map { PhotoWidgetSnapshot.albumDirectoryName(albumId: $0) })
        guard let entries = try? manager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let albumFolders = entries
            .filter { $0.lastPathComponent.hasPrefix("photo-widget-album-") }
            .filter { !keep.contains($0.lastPathComponent) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return left > right
            }
        // Six albums of twelve frames is about seven megabytes; past that the
        // oldest go.
        for folder in albumFolders.dropFirst(6) {
            try? manager.removeItem(at: folder)
        }
    }

    /// The assets a source resolves to, newest first, capped at the number of
    /// frames kept on disk.
    static func assets(for source: PhotoWidgetSettings.Source) -> [PHAsset] {
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
            let upperBound = min(fetch.count, PhotoWidgetSnapshot.maxFrames)
            return (0..<upperBound).map { fetch.object(at: $0) }
        }
    }
}
