import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15b AC-22 — Geometry's Aspect.
struct GeoTransformTests {

    private static let size = 120

    /// A black disc of radius 24 in the middle of a white frame.
    private static func disc() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        let centre = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) + 0.5 - centre, dy = Double(y) + 0.5 - centre
                guard dx * dx + dy * dy <= 24 * 24 else { continue }
                let index = (y * size + x) * 4
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private static func pixels(of image: CIImage) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: size * size * 4)
        context.render(
            image,
            toBitmap: &values,
            rowBytes: size * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
        return values
    }

    /// Darkness summed along the centre row and the centre column: the
    /// disc's width and height in pixels, with its anti-aliased rim counted
    /// by coverage.
    private static func extents(of image: CIImage) -> (width: Double, height: Double) {
        let values = pixels(of: image)
        let middle = size / 2
        var width = 0.0, height = 0.0
        for i in 0..<size {
            width += Double(1 - values[(middle * size + i) * 4])
            height += Double(1 - values[(i * size + middle) * 4])
        }
        return (width, height)
    }

    /// AC-22. Aspect +50 makes the disc 1.5^0.5 ≈ 1.22 times as wide as it
    /// is tall, and no pixel of the frame is left transparent.
    @Test func aspectStretchesAroundTheCentre() {
        var adjustments = PhotoAdjustments()
        adjustments.geoAspect = 0.5
        let output = PhotoRenderService.applyGeo(adjustments, to: Self.disc())

        let disc = Self.extents(of: output)
        let ratio = disc.width / disc.height
        #expect(abs(ratio - 1.22) <= 0.02, "width/height \(ratio) (\(disc.width) × \(disc.height))")

        let values = Self.pixels(of: output)
        let transparent = stride(from: 3, to: values.count, by: 4).filter { values[$0] < 0.999 }.count
        #expect(transparent == 0)
    }

    /// Squeezing is the same stretch turned: the taller axis grows, so the
    /// sides do not pull in.
    @Test func negativeAspectGrowsTheHeight() {
        let scale = PhotoRenderService.aspectScale(-0.5)
        #expect(scale.x == 1)
        #expect(abs(Double(scale.y) - 1.5.squareRoot()) < 1e-9)
        let identity = PhotoRenderService.aspectScale(0)
        #expect(identity.x == 1 && identity.y == 1)
    }
}
