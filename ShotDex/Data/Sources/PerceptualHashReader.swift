import Foundation
import Photos
import UIKit

/// Produces the perceptual hash of a photo. A protocol so the scan pipeline
/// can be driven by a stub in tests.
protocol PerceptualHashReading: Sendable {
    /// `nil` when no rendition could be obtained (iCloud-only asset with
    /// network disallowed, or PhotoKit refusing the asset).
    func hash(for asset: PHAsset, allowNetwork: Bool) async -> PerceptualHash?
}

/// Hashes from a small PhotoKit rendition — never the original. PhotoKit
/// keeps a few-hundred-pixel thumbnail on device for practically every asset,
/// so hashing stays local and cheap even for an "Optimize Storage" library.
struct PerceptualHashReader: PerceptualHashReading {
    /// Rendition edge asked of PhotoKit. Well above the 9×8 sample grid so the
    /// downsample averages real detail, small enough to be served from the
    /// on-device thumbnail set.
    static let renditionEdge: CGFloat = 96

    func hash(for asset: PHAsset, allowNetwork: Bool) async -> PerceptualHash? {
        guard let image = await Self.rendition(for: asset, allowNetwork: allowNetwork),
              let cgImage = image.cgImage
        else { return nil }
        return DifferenceHash.hash(of: cgImage)
    }

    private static func rendition(for asset: PHAsset, allowNetwork: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One callback, never a degraded-then-final pair, so the
            // continuation resumes exactly once.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            options.version = .current
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: renditionEdge, height: renditionEdge),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
