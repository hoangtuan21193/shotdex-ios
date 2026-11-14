import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.18 §4 (AC-8): red where the picture clips white, blue where it clips
/// black, nothing elsewhere; off means no layer.
struct ClippingOverlayTests {
    /// Three columns: white, mid grey, black.
    static func stripes() -> CGImage {
        let width = 3, height = 2
        var pixels = [UInt8]()
        for _ in 0..<height {
            pixels += [255, 255, 255, 255, 128, 128, 128, 255, 0, 0, 0, 255]
        }
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        return context
    }

    static func pixel(_ image: CGImage, x: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        out.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Array(out[(x * 4)..<(x * 4 + 4)])
    }

    @Test func marksOnlyClippedPixels() throws {
        let overlay = try #require(ClippingOverlay.make(from: Self.stripes(), highlights: true, shadows: true))
        #expect(Self.pixel(overlay, x: 0) == [255, 59, 48, 255])
        #expect(Self.pixel(overlay, x: 1)[3] == 0)
        #expect(Self.pixel(overlay, x: 2) == [10, 132, 255, 255])
    }

    @Test func eachLayerAlone() throws {
        let highlights = try #require(ClippingOverlay.make(from: Self.stripes(), highlights: true, shadows: false))
        #expect(Self.pixel(highlights, x: 2)[3] == 0)
        let shadows = try #require(ClippingOverlay.make(from: Self.stripes(), highlights: false, shadows: true))
        #expect(Self.pixel(shadows, x: 0)[3] == 0)
        #expect(ClippingOverlay.make(from: Self.stripes(), highlights: false, shadows: false) == nil)
    }
}
