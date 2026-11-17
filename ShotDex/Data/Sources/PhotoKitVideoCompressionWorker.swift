import CoreGraphics
import Foundation
import Photos

/// `VideoCompressionWorking` over PhotoKit (FS-24 §7): reads the video's
/// original through `OriginalFetching` (iCloud download included), encodes
/// with `VideoCompressionEncoder`, and saves the copy in one change block
/// that carries the capture date, place, favourite and user albums.
struct PhotoKitVideoCompressionWorker: VideoCompressionWorking {
    let fetcher: any OriginalFetching
    /// The app's own deletion path (`PhotoEditingService.deleteAssets(ids:)`),
    /// so a server-backed original is asked about first (FS-19.07 §9) and its
    /// marks go with it.
    let delete: @Sendable ([String]) async throws -> Void

    func preflight(_ id: String) async -> VideoCompressionSource? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              asset.mediaType == .video
        else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        let movie = resources.first { $0.type == .fullSizeVideo } ?? resources.first { $0.type == .video }
        let bytes = (movie?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        return VideoCompressionSource(
            byteCount: bytes,
            duration: asset.duration,
            pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
            // PhotoKit does not say; the estimate assumes the common rate.
            frameRate: 30,
            hasAudio: true
        )
    }

    func fetchOriginal(_ id: String, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw OriginalFetchError.missing
        }
        try await fetcher.fetch(OriginalItem(asset: asset), to: url, progress: progress)
    }

    func encode(_ source: URL, to output: URL, settings: VideoCompressionEncoder.Settings,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        try await VideoCompressionEncoder.encode(source, to: output, settings: settings, progress: progress)
    }

    func save(_ file: URL, copying id: String) async throws -> String {
        guard let original = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw OriginalFetchError.missing
        }
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(original, with: .album, options: nil)
        let name = PHAssetResource.assetResources(for: original)
            .first { $0.type == .video || $0.type == .fullSizeVideo }?.originalFilename
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            if let name {
                options.originalFilename = (name as NSString).deletingPathExtension + ".mp4"
            }
            creation.addResource(with: .video, fileURL: file, options: options)
            creation.creationDate = original.creationDate
            creation.location = original.location
            creation.isFavorite = original.isFavorite
            guard let placeholder = creation.placeholderForCreatedAsset else { return }
            placeholderID = placeholder.localIdentifier
            albums.enumerateObjects { album, _, _ in
                guard album.canPerform(.addContent),
                      let change = PHAssetCollectionChangeRequest(for: album) else { return }
                change.addAssets([placeholder] as NSArray)
            }
        }
        guard let placeholderID else {
            throw VideoCompressionEncoder.EncodeError(errorDescription: String(localized: "Photos didn't save the video.", comment: "Compress Videos: PhotoKit returned no asset"))
        }
        return placeholderID
    }

    func freeBytes() -> Int64? {
        DiskSpace.availableBytes()
    }

    func deleteOriginals(_ ids: [String]) async throws {
        try await delete(ids)
    }
}
