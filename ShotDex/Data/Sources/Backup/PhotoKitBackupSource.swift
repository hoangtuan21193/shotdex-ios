import Foundation
import Photos

/// The Photos library as a backup source (FS-22.02 §1). Under `.limited`
/// access it sees — and so backs up — only the photos the user allowed.
///
/// Listing every asset is cheap; reading an asset's resources is a PhotoKit
/// round trip each. So resources are read only for assets the ledger has not
/// seen or that changed since the last run.
struct PhotoKitBackupSource: BackupSourceReading {
    func items(for job: BackupJob, context: BackupSourceContext) async throws -> [BackupSourceItem] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw BackupSourceError.noPhotosAccess }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        switch job.settings.content {
        case .photosAndVideos:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        case .photosOnly:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videosOnly:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
        let assets = PHAsset.fetchAssets(with: options)

        var toRead: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            let changed = context.lastCheckedAt.map { (asset.modificationDate ?? .distantFuture) > $0 } ?? true
            if !context.handledItemKeys.contains(asset.localIdentifier) || changed {
                toRead.append(asset)
            }
        }
        try Task.checkCancellation()

        let albums = job.settings.organize.levels == .album ? Self.albumNames(for: toRead) : [:]
        var items: [BackupSourceItem] = []
        items.reserveCapacity(toRead.count)
        for asset in toRead {
            try Task.checkCancellation()
            let modified = Int(asset.modificationDate?.timeIntervalSince1970 ?? 0)
            let created = Int(asset.creationDate?.timeIntervalSince1970 ?? 0)
            let files = PhotoKitOriginalExporter.uploadFiles(for: asset).map { file in
                BackupSourceFile(file: file, sourceStamp: Self.stamp(for: file, created: created, modified: modified))
            }
            guard !files.isEmpty else { continue }
            items.append(BackupSourceItem(
                itemKey: asset.localIdentifier,
                date: asset.creationDate ?? asset.modificationDate ?? Date(),
                isVideo: asset.mediaType == .video,
                album: albums[asset.localIdentifier],
                files: files
            ))
        }
        return items
    }

    /// What a file is matched on in the ledger. An original never changes in
    /// Photos; stamping it with the asset's modification time would re-copy
    /// it after every edit. Photos does not always report a size: then the
    /// creation date stands in, never a shared "0". The on-server check
    /// (FS-19.07 §4) stamps files the same way to reuse the ledger's hashes.
    static func stamp(for file: AssetUploadFile, created: Int, modified: Int) -> String {
        let size = file.estimatedBytes > 0 ? "\(file.estimatedBytes)" : "c\(created)"
        return file.role == .original ? size : "\(size):\(modified)"
    }

    /// The first user album (in Photos' order) each asset is in.
    private static func albumNames(for assets: [PHAsset]) -> [String: String] {
        let wanted = Set(assets.map(\.localIdentifier))
        var names: [String: String] = [:]
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { album, _, stopAlbums in
            // Albums are walked one at a time; stop as soon as every asset has
            // one, or when the run is cancelled.
            if Task.isCancelled || names.count == wanted.count {
                stopAlbums.pointee = true
                return
            }
            let title = album.localizedTitle ?? ""
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                if wanted.contains(id), names[id] == nil { names[id] = title }
            }
        }
        return names
    }
}
