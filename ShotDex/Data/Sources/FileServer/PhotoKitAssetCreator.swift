import Foundation
import Photos

/// `AssetCreating` over PhotoKit (FS-17.02 §2): one `performChanges` per
/// photo — the asset, its RAW as the alternate resource the way Photos keeps
/// a camera's RAW + JPEG, its capture date, and the album — so a photo is
/// either fully in the library or not at all.
struct PhotoKitAssetCreator: AssetCreating {
    func createAsset(_ request: AssetCreationRequest) async throws -> String {
        var placeholderId: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                for resource in request.resources {
                    let options = PHAssetResourceCreationOptions()
                    // The work file is deleted by the session afterwards.
                    options.shouldMoveFile = false
                    options.originalFilename = resource.originalFilename
                    let type: PHAssetResourceType = resource.role == .alternatePhoto ? .alternatePhoto : .photo
                    creation.addResource(with: type, fileURL: resource.url, options: options)
                }
                if let date = request.creationDate {
                    creation.creationDate = date
                }
                guard let placeholder = creation.placeholderForCreatedAsset else { return }
                placeholderId = placeholder.localIdentifier
                if let albumId = request.albumId,
                   let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject,
                   let change = PHAssetCollectionChangeRequest(for: album) {
                    change.addAssets([placeholder] as NSArray)
                }
            }
        } catch {
            throw Self.map(error, request: request)
        }
        guard let placeholderId else { throw AssetCreationError.failed(String(localized: "Photos didn't create the photo.", comment: "Download from server: PhotoKit returned no asset")) }
        return placeholderId
    }

    /// Photos rejects a format it can't store with an invalid-resource error;
    /// say which format, not the framework's code.
    private static func map(_ error: Error, request: AssetCreationRequest) -> Error {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.Code.invalidResource.rawValue {
            let format = request.resources.first.map { ($0.originalFilename as NSString).pathExtension.uppercased() } ?? ""
            return AssetCreationError.unsupportedFormat(format)
        }
        return AssetCreationError.failed(error.localizedDescription)
    }

    /// Which of these assets are still in the library — "In Library" only
    /// counts a copy that is still there (FS-17 §4).
    static func existingAssetIds(_ ids: [String]) -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var present = Set<String>()
        result.enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
        return present
    }

    /// `.limited` access: the sheet cannot offer albums (FS-17.02 §1).
    static var isLimitedAccess: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
    }
}
