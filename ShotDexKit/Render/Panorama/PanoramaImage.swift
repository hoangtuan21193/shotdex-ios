import CoreGraphics
import Foundation

/// A single-channel image of the kind the registration stage works on:
/// luminance, 0…1, one `Float` per pixel, no stride and no padding.
///
/// Registration never looks at colour and never looks at a full-resolution
/// frame. It runs on a long edge of about 1024 px (`PanoramaImage.workingEdge`),
/// which is where the spike measured 0.2–0.3 px homography error — so this type
/// is small enough to hold several of at once, and holding them is the point:
/// every pair of frames is compared, and decoding each one twice would cost
/// more than the comparison.
public struct PanoramaImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` values in 0…1.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height, "pixel count must match the size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The long edge registration works at. From the spike: big enough for
    /// sub-pixel homography, small enough that comparing every pair of a
    /// ten-frame set takes a third of a second.
    public static let workingEdge = 1_024

    @inlinable
    public subscript(x: Int, y: Int) -> Float {
        pixels[y * width + x]
    }

    /// Luminance of a `CGImage`, scaled so its long edge is at most
    /// `maximumEdge`.
    ///
    /// Drawn through Core Graphics at 8 bits of grey rather than read from the
    /// source's own buffer: a frame arrives in whatever colour space and
    /// bitmap layout its camera wrote, and registration wants one number per
    /// pixel with no branch for the twelve ways that can be spelled. The
    /// interpolation is Core Graphics', which is enough — this image is used to
    /// find corners, not to be looked at.
    public static func luminance(of image: CGImage, maximumEdge: Int = workingEdge) -> PanoramaImage? {
        let sourceWidth = image.width, sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let scale = min(1, Double(maximumEdge) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))

        var bytes = [UInt8](repeating: 0, count: width * height)
        let drew: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        var pixels = [Float](repeating: 0, count: width * height)
        for index in 0..<pixels.count {
            pixels[index] = Float(bytes[index]) / 255
        }
        return PanoramaImage(width: width, height: height, pixels: pixels)
    }

    /// A 3×3 box blur, run before the descriptor samples its pairs.
    ///
    /// A binary descriptor compares single pixels, so on an unsmoothed image it
    /// is reading sensor noise as often as it is reading the scene — two frames
    /// of the same wall then describe differently. One cheap pass fixes that;
    /// the classic recipe smooths more, but these frames are already downscaled
    /// from 24 MP, which did most of the smoothing.
    public func blurred() -> PanoramaImage {
        guard width > 2, height > 2 else { return self }
        var output = pixels
        pixels.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        var sum: Float = 0
                        for dy in -1...1 {
                            let row = (y + dy) * width + x
                            sum += input[row - 1] + input[row] + input[row + 1]
                        }
                        out[y * width + x] = sum / 9
                    }
                }
            }
        }
        return PanoramaImage(width: width, height: height, pixels: output)
    }
}
