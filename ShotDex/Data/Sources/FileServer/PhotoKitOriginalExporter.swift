import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// One asset as the upload plans it: its files and the date its folder is
/// named after.
struct AssetUploadEntry: Sendable {
    let assetId: String
    let captureDate: Date
    let files: [AssetUploadFile]
    /// The date the copy on the server gets (FS-19.08 §6e): when it was
    /// taken, else when Photos last changed it — never "now", which
    /// `captureDate` falls back to for the folder name.
    var takenAt: Date?
}

/// Reads an asset's files out of Photos for the upload (FS-15.02 §2, §4).
///
/// Straight from `PHAssetResourceManager`, which hands over the file as it
/// was imported — the original bytes, EXIF untouched — and fetches it from
/// iCloud when the device holds only the Optimize Storage proxy. Never an
/// image request: those return renditions.
struct PhotoKitOriginalExporter: AssetFileExporting {
    /// Resource types that are what the camera or the import wrote.
    private static let originalTypes: Set<PHAssetResourceType> = [.photo, .alternatePhoto, .video, .pairedVideo, .audio]
    /// Resource types that are the render of an edit made in Photos.
    private static let editedTypes: Set<PHAssetResourceType> = [.fullSizePhoto, .fullSizeVideo, .fullSizePairedVideo]

    static func key(for resource: PHAssetResource) -> String {
        "\(resource.type.rawValue):\(resource.originalFilename)"
    }

    /// Every file of every asset asked for. Enumerating resources is a
    /// PhotoKit round trip per asset, so callers run this off the main actor.
    static func entries(for assetIds: [String]) -> [AssetUploadEntry] {
        let assets = PhotoLibraryService.fetchAssets(ids: assetIds)
        return assets.map { asset in
            let files = uploadFiles(for: asset)
            return AssetUploadEntry(
                assetId: asset.localIdentifier,
                captureDate: asset.creationDate ?? Date(),
                files: files,
                takenAt: asset.creationDate ?? asset.modificationDate
            )
        }
    }

    /// The asset's originals and edited renders, in resource order — one
    /// PhotoKit round trip.
    static func uploadFiles(for asset: PHAsset) -> [AssetUploadFile] {
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryName = resources.first { originalTypes.contains($0.type) }?.originalFilename
        return resources.compactMap { uploadFile(for: $0, primaryName: primaryName) }
    }

    /// One resource as the upload sees it; nil for resources that are
    /// neither an original nor an edit's render (adjustment data, thumbnails).
    /// `primaryName` is the asset's first original, which an edited render is
    /// named after.
    static func uploadFile(for resource: PHAssetResource, primaryName: String?) -> AssetUploadFile? {
        let role: AssetUploadFile.Role
        if originalTypes.contains(resource.type) {
            role = .original
        } else if editedTypes.contains(resource.type) {
            role = .edited
        } else {
            return nil
        }
        let isRAW = UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false
        // An edited render is called FullSizeRender.jpg in Photos;
        // on the server it sits beside its original as IMG_1234_edited.jpg.
        let filename = role == .edited
            ? ServerUploadPath.editedFilename(original: primaryName ?? resource.originalFilename, rendered: resource.originalFilename)
            : resource.originalFilename
        return AssetUploadFile(
            key: key(for: resource),
            filename: filename,
            isRAW: isRAW,
            role: role,
            estimatedBytes: (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        )
    }

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first else {
            throw RemoteFileError.other(String(localized: "The photo is no longer in your library.", comment: "Upload to Server: asset deleted mid-batch"))
        }
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { Self.key(for: $0) == file.key }) else {
            throw RemoteFileError.other(String(localized: "This file of the photo is no longer available.", comment: "Upload to Server: resource vanished mid-batch"))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(file.filename)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await Self.stream(resource, to: url, options: options)
        } catch {
            try? FileManager.default.removeItem(at: url)
            if Task.isCancelled { throw CancellationError() }
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
                throw RemoteFileError.other(String(localized: "Not enough space on this device to prepare the file.", comment: "Upload to Server: no room to stage one original"))
            }
            throw error
        }
        return url
    }

    /// The original, streamed to `url` chunk by chunk, and cancelled with the
    /// task — Pause must stop a multi-GB iCloud download at once, which
    /// `writeData` does not (FS-22.02 §4).
    private static func stream(_ resource: PHAssetResource, to url: URL, options: PHAssetResourceRequestOptions) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let manager = PHAssetResourceManager.default()
        let request = OSAllocatedUnfairLock<PHAssetResourceDataRequestID?>(initialState: nil)
        let writeError = OSAllocatedUnfairLock<Error?>(initialState: nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let id = manager.requestData(for: resource, options: options) { chunk in
                    do { try handle.write(contentsOf: chunk) } catch { writeError.withLock { $0 = $0 ?? error } }
                } completionHandler: { error in
                    if let error = error ?? writeError.withLock({ $0 }) {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
                request.withLock { $0 = id }
            }
        } onCancel: {
            if let id = request.withLock({ $0 }) { manager.cancelDataRequest(id) }
        }
    }
}
