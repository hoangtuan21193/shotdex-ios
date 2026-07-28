import Foundation
import Photos

extension PhotoMetadata {
    /// Placeholder row for an asset that has not been indexed yet —
    /// PhotoKit facts only, no EXIF.
    static func placeholder(for asset: PHAsset) -> PhotoMetadata {
        PhotoMetadata(
            assetId: asset.localIdentifier,
            creationDate: asset.creationDate.map { Int($0.timeIntervalSince1970) },
            modificationDate: asset.modificationDate.map { Int($0.timeIntervalSince1970) },
            mediaType: asset.mediaType.rawValue,
            cameraManufacturer: nil, cameraModel: nil,
            normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil,
            iso: nil, aperture: nil,
            shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil,
            width: asset.pixelWidth > 0 ? asset.pixelWidth : nil,
            height: asset.pixelHeight > 0 ? asset.pixelHeight : nil,
            fileSize: nil, latitude: nil, longitude: nil,
            isFavorite: asset.isFavorite,
            indexedAt: 0,
            exifStatus: ExifStatus.noExif.rawValue
        )
    }
}

extension LibraryGridItem {
    /// Slim grid row for an asset that has not been indexed yet — identity,
    /// creation date (for section headers) and pixel dimensions (cheap on
    /// `PHAsset`, so the megapixels badge works pre-index); exposure fields
    /// and file size are nil until the index pass fills them.
    init(asset: PHAsset) {
        self.init(
            assetId: asset.localIdentifier,
            creationDate: asset.creationDate.map { Int($0.timeIntervalSince1970) },
            mediaType: asset.mediaType.rawValue,
            originalFilename: nil,
            iso: nil,
            aperture: nil,
            shutterSpeedDisplay: nil,
            focalLength: nil,
            equivalentFocalLength: nil,
            width: asset.pixelWidth > 0 ? asset.pixelWidth : nil,
            height: asset.pixelHeight > 0 ? asset.pixelHeight : nil,
            fileSize: nil
        )
    }
}
