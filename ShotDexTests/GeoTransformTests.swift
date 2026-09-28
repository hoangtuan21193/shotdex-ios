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

    /// 300×200 grey with a 3px red rim: anything sampled from outside the
    /// photo is a smear of that rim.
    private static func rimmed() -> CIImage {
        let width = 300, height = 200
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rim = x < 3 || y < 3 || x >= width - 3 || y >= height - 3
                let index = (y * width + x) * 4
                pixels[index] = rim ? 1 : 0.5
                pixels[index + 1] = rim ? 0 : 0.5
                pixels[index + 2] = rim ? 0 : 0.5
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    /// Red pixels more than 4px in from the frame's edge — the smear — and
    /// transparent pixels anywhere.
    private static func smearAndHoles(_ image: CIImage) -> (smear: Int, holes: Int) {
        let width = 300, height = 200
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &values, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: nil)
        var smear = 0, holes = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if values[index + 3] < 0.999 { holes += 1 }
                let inner = x >= 4 && y >= 4 && x < width - 4 && y < height - 4
                if inner, values[index] - values[index + 1] > 0.2 { smear += 1 }
            }
        }
        return (smear, holes)
    }

    /// AC-29. A 3:2 photo, Vertical +40: with Constrain Crop the frame is
    /// still 3:2 and holds nothing from outside the photo; without it the
    /// edges are stretched in, and nothing is transparent either way.
    @Test func constrainCropKeepsTheLockedRatio() {
        var adjustments = PhotoAdjustments()
        adjustments.geoVertical = 0.4
        let loose = PhotoRenderService.applyGeo(adjustments, to: Self.rimmed())
        adjustments.geoConstrainCrop = 1
        let constrained = PhotoRenderService.applyGeo(adjustments, to: Self.rimmed())

        #expect(abs(constrained.extent.width / constrained.extent.height - 1.5) <= 0.01)
        let tight = Self.smearAndHoles(constrained)
        #expect(tight.smear == 0, "\(tight.smear) smeared pixels with Constrain Crop")
        #expect(tight.holes == 0)

        let stretched = Self.smearAndHoles(loose)
        #expect(stretched.smear > 100, "without it the edges stretch in (\(stretched.smear))")
        #expect(stretched.holes == 0)
    }

    /// Nothing to straighten, nothing to crop: the toggle alone changes no
    /// pixel.
    @Test func constrainCropAloneIsIdentity() {
        var adjustments = PhotoAdjustments()
        adjustments.geoConstrainCrop = 1
        let input = Self.rimmed()
        #expect(PhotoRenderService.applyGeo(adjustments, to: input) === input)
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
