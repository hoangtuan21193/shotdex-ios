import CoreImage
import Foundation
import ShotDexKit

/// Share as JPEG (FS-08.06 §5): a full-size JPEG of a RAW, developed with
/// the decoder's defaults — the photo as it comes off the camera, not an
/// edit — carrying the RAW's metadata filtered by the share's level.
enum ShareRAWRenderer {
    enum Failure: Error, Equatable {
        /// iOS on this device cannot decode the RAW (FS-03.04b).
        case unreadable
        case cannotWrite
    }

    static let quality = 0.95

    /// Renders `raw` to a JPEG at `destination`. Full size: no scale factor,
    /// the decoder's native output, upright.
    static func renderJPEG(from raw: URL, to destination: URL, level: MetadataLevel) throws {
        guard let filter = CIRAWFilter(imageURL: raw), let image = filter.outputImage else {
            throw Failure.unreadable
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let plain = destination.deletingLastPathComponent()
            .appendingPathComponent("render-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: plain) }
        let context = CIContext(options: [.cacheIntermediates: false])
        do {
            try context.writeJPEGRepresentation(
                of: image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)),
                to: plain,
                colorSpace: space,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
            )
        } catch {
            throw Failure.cannotWrite
        }
        try MetadataRewriter.rewrite(plain, metadataFrom: raw, to: destination, level: level)
    }
}
