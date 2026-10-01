import Foundation
import ImageIO

/// A width and height in pixels.
struct PixelSize: Equatable, Hashable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var longEdge: Int { max(width, height) }

    /// The size as it is shown: an orientation that turns the image a
    /// quarter (5…8 in EXIF terms) swaps width and height.
    func oriented(_ orientation: CGImagePropertyOrientation) -> PixelSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: PixelSize(width: height, height: width)
        default: self
        }
    }
}

/// Whether the bytes on hand are the original (FS-02.06 §3). With the
/// network off PhotoKit still labels an Optimize Storage preview as the
/// final result, so the label is never enough: the pixel count is what
/// decides.
enum OriginalCompleteness {
    /// The original: exactly the photo's width × height once the file's
    /// orientation is applied. `photo` is the size PhotoKit reports for the
    /// asset, which is already the shown size.
    static func isOriginal(
        received: PixelSize,
        orientation: CGImagePropertyOrientation = .up,
        photo: PixelSize
    ) -> Bool {
        guard photo.width > 0, photo.height > 0 else { return false }
        return received.oriented(orientation) == photo
    }

    /// A rendition asked for at a size (Collage): its long edge is at least
    /// 90% of the smaller of the size asked for and the photo's own long
    /// edge — the viewer's threshold (FS-02.01 §4).
    static func isSufficient(received: PixelSize, requestedLongEdge: Int, photo: PixelSize) -> Bool {
        let needed = min(requestedLongEdge, photo.longEdge)
        guard needed > 0 else { return false }
        return received.longEdge * 10 >= needed * 9
    }

    /// The stored size and orientation of an image file, read from its
    /// header without decoding it. `nil` when the file is not an image.
    static func measure(_ url: URL) -> (size: PixelSize, orientation: CGImagePropertyOrientation)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return measure(source)
    }

    static func measure(_ data: Data) -> (size: PixelSize, orientation: CGImagePropertyOrientation)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return measure(source)
    }

    private static func measure(_ source: CGImageSource) -> (size: PixelSize, orientation: CGImagePropertyOrientation)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let raw = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (PixelSize(width: width, height: height), CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }
}

/// What a check with the network off found for one photo's original.
enum OriginalAvailability: Equatable, Sendable {
    /// A full-size original is on this device.
    case local
    /// Only a preview is on this device, or nothing at all: the original is
    /// in iCloud.
    case inCloud
    /// The check could not tell (no image came back and no error said why).
    case unknown

    /// The verdict for what an offline request handed back. A preview that
    /// PhotoKit calls final is still a preview (AC-11).
    static func judge(received: PixelSize?, orientation: CGImagePropertyOrientation = .up, photo: PixelSize) -> Self {
        guard let received else { return .inCloud }
        return OriginalCompleteness.isOriginal(received: received, orientation: orientation, photo: photo) ? .local : .inCloud
    }
}
