import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// The library's side of Export… (FS-03.07b §3, §9): what each asset is made
/// of, and its bytes, read with `PHAssetResourceManager` — the file as it was
/// imported, EXIF untouched, never a rendition — in blocks straight into the
/// destination. A resource only in iCloud downloads on the way.
struct PhotoKitExportSource: ExportAssetSource {
    /// Photos it asks before reading; the scripted one plays a download for
    /// a photo it calls "in iCloud" on a simulator (FS-02.06).
    var fetcher: (any OriginalFetching)?

    private static func role(of type: PHAssetResourceType) -> FileExportSourceFile.Role? {
        switch type {
        case .photo: .photo
        case .alternatePhoto: .alternatePhoto
        case .video: .video
        case .pairedVideo: .pairedVideo
        case .audio: .audio
        case .fullSizePhoto: .editedPhoto
        case .fullSizeVideo: .editedVideo
        case .fullSizePairedVideo: .editedPairedVideo
        default: nil
        }
    }

    static func key(for resource: PHAssetResource) -> String {
        PhotoKitOriginalExporter.key(for: resource)
    }

    /// The picked assets as export items, with the camera and lens the
    /// filter chips use. A PhotoKit round trip per asset: off the main actor.
    static func items(for assetIds: [String], metadata: [String: PhotoMetadata]) -> [FileExportItem] {
        PhotoLibraryService.fetchAssets(ids: assetIds).map { asset in
            let resources = PHAssetResource.assetResources(for: asset)
            let files: [FileExportSourceFile] = resources.compactMap { resource in
                guard let role = role(of: resource.type) else { return nil }
                return FileExportSourceFile(
                    key: key(for: resource),
                    filename: resource.originalFilename,
                    role: role,
                    isRAW: UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false,
                    byteCount: (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                )
            }
            let primary = files.first { $0.role == .photo || $0.role == .video } ?? files.first
            let row = metadata[asset.localIdentifier]
            let kind: FileExportItem.Kind = asset.mediaType == .video
                ? .video
                : (asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo)
            return FileExportItem(
                id: asset.localIdentifier,
                filename: primary?.filename ?? "Photo",
                captureDate: asset.creationDate ?? Date(),
                camera: row?.normalizedCameraModel,
                lens: row?.normalizedLensModel,
                kind: kind,
                files: files,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
    }

    func copy(
        _ file: FileExportSourceFile,
        of item: FileExportItem,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject else {
            // Deleted, or taken out of a limited selection, mid-batch.
            throw FileExportFailure.noLongerAvailable
        }
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { Self.key(for: $0) == file.key }) else {
            throw FileExportFailure.noLongerAvailable
        }
        if let fetcher {
            // A scripted iCloud plays its download first; PhotoKit's own
            // download happens inside the read below.
            try await fetcher.scriptedTransfer(for: item.id, progress: progress)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        let writer = BlockWriter(handle: handle)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress($0) }
        let manager = PHAssetResourceManager.default()
        let request = OSAllocatedUnfairLock<PHAssetResourceDataRequestID?>(initialState: nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let id = manager.requestData(for: resource, options: options) { chunk in
                    writer.write(chunk)
                } completionHandler: { error in
                    let writeError = writer.close()
                    if let writeError { continuation.resume(throwing: writeError) }
                    else if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
                request.withLock { $0 = id }
                if Task.isCancelled { manager.cancelDataRequest(id) }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelDataRequest(id) }
        }
        try Task.checkCancellation()
    }
}

/// Writes PhotoKit's chunks as they arrive; the first write error sticks.
private final class BlockWriter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let handle: FileHandle
    private var error: Error?

    init(handle: FileHandle) { self.handle = handle }

    func write(_ chunk: Data) {
        lock.withLock {
            guard error == nil else { return }
            do { try handle.write(contentsOf: chunk) } catch { self.error = error }
        }
    }

    func close() -> Error? {
        lock.withLock {
            try? handle.close()
            return error
        }
    }
}
