import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// What each stack mode does to real pixels, pinned before the Combine Photos
/// menu is renamed around it (FS-01.09 AC-4): the rename must not move a
/// single value.
struct PhotoStackRendererTests {

    private let side = 16

    // MARK: Fixtures

    /// One flat sRGB colour, components 0…1.
    private func solid(_ r: Double, _ g: Double, _ b: Double, side: Int? = nil) -> CIImage {
        let side = side ?? self.side
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Components in sRGB itself: `CGColor(red:green:blue:alpha:)` is Generic
        // RGB, which the context would convert and shift every value.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        context.setFillColor(CGColor(colorSpace: space, components: [r, g, b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return CIImage(cgImage: context.makeImage()!)
    }

    /// Seeded noise on one half, its own average grey on the other: detail
    /// where the frame is "in focus", nothing where it is not. Noise rather than
    /// stripes so the registration step has one answer, not one per period.
    private func halfSharp(side: Int, sharpOnLeft: Bool) -> CIImage {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for y in 0..<side {
            for x in 0..<side {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let noise = UInt8(truncatingIfNeeded: state >> 56)
                let isSharp = (x < side / 2) == sharpOnLeft
                let value: UInt8 = isSharp ? noise : 128
                let i = (y * side + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return CIImage(cgImage: image)
    }

    // MARK: Reading back

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// sRGB components 0…1 at (x, y), top-left origin.
        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * width + x) * 4
            return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
        }

        /// Standard deviation of the red channel over a column range.
        func spread(columns: Range<Int>) -> Double {
            var values: [Double] = []
            for y in 0..<height { for x in columns { values.append(rgb(x, y).0) } }
            let mean = values.reduce(0, +) / Double(values.count)
            return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
        }
    }

    private func render(_ images: [CIImage], _ mode: PhotoStackMode) async throws -> Pixels {
        let renderer = PhotoStackRenderer()
        let combined = try await renderer.combine(images: images, mode: mode)
        let cgImage = try await renderer.render(combined)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
    }

    // The renderer's context works in linear light, so an average is taken on
    // linearised values — the expected numbers do the same.
    private func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    private func encoded(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 2.0 / 255,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) <= tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    // MARK: Modes

    @Test func lightenKeepsTheBrighterValueOfEachChannel() async throws {
        let pixels = try await render([solid(0.2, 0.8, 0.5), solid(0.6, 0.3, 0.5)], .lighten)
        let (r, g, b) = pixels.rgb(side / 2, side / 2)
        expectClose(r, 0.6); expectClose(g, 0.8); expectClose(b, 0.5)
    }

    @Test func darkenKeepsTheDarkerValueOfEachChannel() async throws {
        let pixels = try await render([solid(0.2, 0.8, 0.5), solid(0.6, 0.3, 0.5)], .darken)
        let (r, g, b) = pixels.rgb(side / 2, side / 2)
        expectClose(r, 0.2); expectClose(g, 0.3); expectClose(b, 0.5)
    }

    @Test func averageWeighsEveryFrameEquallyInLinearLight() async throws {
        let values = [0.1, 0.5, 0.9]
        let pixels = try await render(values.map { solid($0, $0, $0) }, .average)
        let expected = encoded(values.map(linear).reduce(0, +) / Double(values.count))
        expectClose(pixels.rgb(side / 2, side / 2).0, expected)
    }

    @Test func averageOfManyFramesDoesNotDriftTowardsTheLastOne() async throws {
        // Twelve frames, eleven black and one white last: a running mean with the
        // wrong weights ends near white.
        let frames = Array(repeating: solid(0, 0, 0), count: 11) + [solid(1, 1, 1)]
        let pixels = try await render(frames, .average)
        expectClose(pixels.rgb(side / 2, side / 2).0, encoded(1.0 / 12))
    }

    @Test func focusStackKeepsTheDetailedHalfOfEachFrame() async throws {
        let size = 128
        let leftSharp = halfSharp(side: size, sharpOnLeft: true)
        let rightSharp = halfSharp(side: size, sharpOnLeft: false)
        let pixels = try await render([leftSharp, rightSharp], .focusStack)
        // Away from the middle seam, where the masks are softened on purpose.
        let left = pixels.spread(columns: 8..<(size / 2 - 16))
        let right = pixels.spread(columns: (size / 2 + 16)..<(size - 8))
        let flat = try await render([leftSharp, leftSharp], .focusStack).spread(columns: (size / 2 + 16)..<(size - 8))
        #expect(left > 0.15, "left half lost its detail: \(left)")
        #expect(right > 0.15, "right half lost its detail: \(right)")
        #expect(flat < 0.02, "a half that is flat in every frame stays flat: \(flat)")
    }

    // MARK: Frame handling

    @Test func fewerThanTwoFramesIsRefused() async {
        await #expect(throws: PhotoStackError.self) {
            _ = try await PhotoStackRenderer().combine(images: [solid(0.5, 0.5, 0.5)], mode: .average)
        }
    }

    @Test func theFirstFrameSetsTheOutputSize() async throws {
        let pixels = try await render([solid(0.4, 0.4, 0.4, side: 8), solid(0.4, 0.4, 0.4, side: 32)], .lighten)
        #expect(pixels.width == 8)
        #expect(pixels.height == 8)
    }

    @Test func everyModeIsCovered() {
        // A fifth mode added without a case here would ship untested.
        #expect(PhotoStackMode.allCases == [.average, .lighten, .darken, .focusStack])
    }
}
