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

    func write(designId: String, settings: PhotoWidgetSettings) async {
        guard let container = WidgetSharedContainer.url else { return }
        let directory = PhotoWidgetSnapshot.directoryURL(
            named: PhotoWidgetDesign.directoryName(id: designId), in: container
        )
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

        let snapshot = PhotoWidgetSnapshot(
            frames: frames,
            generatedAt: .now,
            renderedPixels: Int(WidgetImageRenderer.maxPixels),
            rendererVersion: WidgetImageRenderer.version,
            sourceId: Self.sourceId(of: settings.source)
        )
        try? WidgetSharedContainer.encode(
            snapshot,
            to: directory.appendingPathComponent(PhotoWidgetSnapshot.fileName)
        )
        WidgetImageRenderer.prune(
            directory: directory,
            keeping: Set(frames.map(\.fileName) + [PhotoWidgetSnapshot.fileName])
        )
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
    }

    /// Redoes the album and single-photo folders that were rendered at the old
    /// size, so a widget pointed at an album from the Home Screen gets the
    /// same sharpness as one set up in the app.
    func refreshStaleFolders() async {
        guard let container = WidgetSharedContainer.url else { return }
        let target = Int(WidgetImageRenderer.maxPixels)
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: container, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for folder in entries {
            let name = folder.lastPathComponent
            let isAlbum = name.hasPrefix("photo-widget-album-")
            let isAsset = name.hasPrefix("photo-widget-asset-")
            guard isAlbum || isAsset else { continue }
            let snapshot = PhotoWidgetSnapshot.read(directoryName: name)
            guard !snapshot.frames.isEmpty,
                  snapshot.isBelow(pixels: target, rendererVersion: WidgetImageRenderer.version)
            else { continue }
            // The identifier is not recoverable from the folder name (it was
            // slugged), so the assets are found from the frames themselves.
            let assets = PhotoLibraryService.fetchAssets(ids: snapshot.frames.map(\.assetId))
            guard !assets.isEmpty else { continue }
            await write(assets: assets, to: folder, sourceId: snapshot.sourceId)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
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
            let directoryName = request.frameDirectoryName
            let directory = PhotoWidgetSnapshot.directoryURL(named: directoryName, in: container)
            let source: PhotoWidgetSettings.Source = switch request.source {
            case .album: .album(collectionId: request.albumId, title: request.title)
            case .photo: .photo(assetId: request.albumId)
            }
            let assets = Self.assets(for: source)
            let sourceId = Self.sourceId(of: source)
            // An album that no longer exists still counts as answered: leaving
            // the ask queued would have the widget re-request it for ever.
            guard !assets.isEmpty else {
                fulfilled.insert(request.albumId)
                continue
            }
            await write(assets: assets, to: directory, sourceId: sourceId)
            fulfilled.insert(request.albumId)
        }

        PhotoWidgetFrameRequests.clear(albumIds: fulfilled)
        Self.pruneAlbumFolders(in: container, keeping: fulfilled)
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
        return fulfilled.count
    }

    /// Renders a set of assets into one folder and writes its snapshot.
    private func write(assets: [PHAsset], to directory: URL, sourceId: String? = nil) async {
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
            PhotoWidgetSnapshot(
                frames: frames,
                generatedAt: .now,
                renderedPixels: Int(WidgetImageRenderer.maxPixels),
                rendererVersion: WidgetImageRenderer.version,
                sourceId: sourceId
            ),
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
        let keep = Set(
            albumIds.flatMap {
                [
                    PhotoWidgetSnapshot.albumDirectoryName(albumId: $0),
                    PhotoWidgetSnapshot.assetDirectoryName(assetId: $0),
                ]
            }
        )
        guard let entries = try? manager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let albumFolders = entries
            .filter {
                $0.lastPathComponent.hasPrefix("photo-widget-album-")
                    || $0.lastPathComponent.hasPrefix("photo-widget-asset-")
            }
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

    /// What a source is, as the one identifier a snapshot records.
    static func sourceId(of source: PhotoWidgetSettings.Source) -> String? {
        switch source {
        case .none: nil
        case .photo(let assetId): assetId
        case .album(let collectionId, _): collectionId
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
