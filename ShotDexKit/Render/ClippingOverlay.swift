import CoreGraphics
import Foundation

/// Where the picture clips, as a layer to lay over it (FS-03.18 §4): red where
/// any channel is at or above 254 (highlights), blue where every channel is at
/// or below 1 (shadows) — the thresholds the histogram counts with. Lightroom
/// shows the same on its loupe; ShotDex turns it on from the histogram's
/// triangles.
public enum ClippingOverlay {
    public static let highlightThreshold: UInt8 = 254
    public static let shadowThreshold: UInt8 = 1

    /// A transparent image the size of `image` (scaled to at most
    /// `maximumEdge`), opaque red / blue where it clips. Nil when neither is
    /// asked for or the image cannot be read.
    public static func make(from image: CGImage, highlights: Bool, shadows: Bool,
                            maximumEdge: Int = 1_024) -> CGImage? {
        guard highlights || shadows else { return nil }
        let scale = min(1, Double(maximumEdge) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let bytesPerRow = width * 4
        var source = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn = source.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: info)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var overlay = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: source.count, by: 4) {
            let r = source[index], g = source[index + 1], b = source[index + 2]
            if highlights, max(r, max(g, b)) >= highlightThreshold {
                overlay[index] = 255; overlay[index + 1] = 59; overlay[index + 2] = 48; overlay[index + 3] = 255
            } else if shadows, max(r, max(g, b)) <= shadowThreshold {
                overlay[index] = 10; overlay[index + 1] = 132; overlay[index + 2] = 255; overlay[index + 3] = 255
            }
        }
        return overlay.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: info)?.makeImage()
        }
    }
}
