import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15d AC-45 — a mask's Moiré (and its Defringe).
struct MaskLocalDetailTests {

    static let size = 96

    /// Green and purple stripes 3px wide at the same Rec. 709 luminance —
    /// the colour moiré a fine fabric throws.
    static func stripes() -> CIImage {
        let purple: SIMD3<Float> = [0.55, 0.25, 0.6]
        let luma: Float = 0.2126 * purple.x + 0.7152 * purple.y + 0.0722 * purple.z
        let green: SIMD3<Float> = [0.2, (luma - 0.2126 * 0.2 - 0.0722 * 0.2) / 0.7152, 0.2]
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let colour = (x / 3).isMultiple(of: 2) ? green : purple
                let index = (y * size + x) * 4
                pixels[index] = colour.x; pixels[index + 1] = colour.y; pixels[index + 2] = colour.z
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: size * 16, size: CGSize(width: size, height: size),
                       format: .RGBAf, colorSpace: nil)
    }

    static func rgb(_ image: CIImage) -> [SIMD3<Double>] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: size * size * 4)
        context.render(image, toBitmap: &values, rowBytes: size * 16,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: nil)
        var out: [SIMD3<Double>] = []
        for y in 8..<(size - 8) {
            for x in 8..<(size - 8) {
                let i = (y * size + x) * 4
                out.append(SIMD3(Double(values[i]), Double(values[i + 1]), Double(values[i + 2])))
            }
        }
        return out
    }

    static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func chromaVariance(_ pixels: [SIMD3<Double>]) -> Double {
        let chroma = pixels.map { $0 - SIMD3(repeating: luma($0)) }
        let mean = chroma.reduce(SIMD3<Double>.zero, +) / Double(chroma.count)
        return chroma.map { (($0 - mean) * ($0 - mean)).sum() }.reduce(0, +) / Double(chroma.count)
    }

    /// AC-45. Moiré 80 over the stripes: chroma variance drops to half or
    /// less; luminance moves 1/255 at most. (Outside the mask nothing moves
    /// because mask adjustments reach the photo only through the matte — the
    /// corner tests in MaskLocalColorTests and KernelPipelineGoldenTests hold
    /// that line for every mask control.)
    @Test func moireFlattensColourStripes() {
        let input = Self.stripes()
        var mask = PhotoMask(name: "Fabric", component: PhotoMaskComponent(kind: .radialGradient))
        mask.adjustments.maskMoire = 0.8
        let output = PhotoRenderService.applyMaskAdjustments(of: mask, to: input)

        let before = Self.rgb(input), after = Self.rgb(output)
        let share = Self.chromaVariance(after) / Self.chromaVariance(before)
        #expect(share <= 0.5, "chroma variance kept \(share)")
        let worst = zip(before, after).map { abs(Self.luma($0) - Self.luma($1)) }.max() ?? 1
        #expect(worst <= 1.0 / 255, "luminance moved \(worst)")
    }

    /// A mask's Defringe reaches every hue, not only purple and green.
    @Test func maskDefringeTakesEveryHue() {
        // An orange fringe on a black/white step: outside both global bands.
        let size = 64
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                var rgb: SIMD3<Float> = x < 30 ? [0.05, 0.05, 0.05] : [0.95, 0.95, 0.95]
                if x == 30 || x == 31 { rgb = [0.8, 0.45, 0.1] }
                let i = (y * size + x) * 4
                pixels[i] = rgb.x; pixels[i + 1] = rgb.y; pixels[i + 2] = rgb.z
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let input = CIImage(bitmapData: data, bytesPerRow: size * 16, size: CGSize(width: size, height: size),
                            format: .RGBAf, colorSpace: nil)
        let output = PhotoRenderService.applyMaskDefringe(1, to: input)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var v = [Float](repeating: 0, count: 4)
        context.render(output, toBitmap: &v, rowBytes: 16, bounds: CGRect(x: 30, y: 32, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        #expect(v[0] - v[2] < 0.35, "the orange fringe kept \(v[0] - v[2]) of its 0.7 spread")
    }
}
