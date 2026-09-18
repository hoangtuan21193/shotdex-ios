import ImageIO
import Photos
import UIKit

extension PhotoLibraryService {

    /// Whether this photo has been edited, and so has an original worth
    /// comparing against.
    ///
    /// Read from its resources, because `PHAsset` carries no edited flag. This
    /// is affordable for the one photo in the viewer and nowhere near
    /// affordable for a scrolling grid, which is why the grid has no edited
    /// badge.
    nonisolated static func hasEdits(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset)
            .contains { $0.type == .adjustmentData }
    }

    /// The photo as it came off the camera, ignoring every edit since.
    ///
    /// Asked for as **data**, not as a rendition. `requestImage` with
    /// `version = .original` came back as the edited frame — measured: holding
    /// an edited photo showed the edit again, with no visible change at all.
    /// The data path hands back the original file's bytes, which cannot be
    /// confused with a rendered version of anything.
    func requestOriginalImage(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let scale = targetSize.width * targetSize.height
        return imageManager.requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, _, _, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !cancelled, let data else {
                Task { @MainActor in completion(nil) }
                return
            }
            // Downsampled off the main actor to roughly what the screen needs:
            // a 48-megapixel original decoded whole, for a comparison held for
            // a second, is memory nobody asked to spend.
            Task.detached(priority: .userInitiated) {
                let image = Self.downsampledImage(data: data, pixelBudget: scale)
                await MainActor.run { completion(image) }
            }
        }
    }

    /// Decodes the original's bytes straight to roughly the size the screen
    /// needs. `WithTransform` applies the file's orientation, so the caller
    /// never has to carry one around.
    private nonisolated static func downsampledImage(
        data: Data,
        pixelBudget: CGFloat
    ) -> UIImage? {
        let maximumEdge = max(320, sqrt(max(pixelBudget, 1)))
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
