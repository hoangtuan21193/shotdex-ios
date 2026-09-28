import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15b AC-16…AC-18 — the three noise-reduction sliders Lightroom splits
/// out: NR Contrast, Color Detail, Color Smoothness. The FS-03.11 half of this
/// suite lives in `EditorParityTests.swift`.
extension NoiseReductionSplitTests {

    private static let size = 96

    /// A luminance step (0.3 left, 0.7 right, edge at x = 48) under ±0.08 of
    /// seeded grey noise.
    private static func steppedFrame() -> CIImage {
        var generator = SplitSeededGenerator(seed: 16)
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let base: Float = x < size / 2 ? 0.3 : 0.7
                let value = base + Float.random(in: -0.08...0.08, using: &generator)
                let index = (y * size + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        return image(pixels)
    }

    private static func image(_ pixels: [Float]) -> CIImage {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private static func red(of image: CIImage, in rect: CGRect) -> [Double] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let width = Int(rect.width), height = Int(rect.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: rect,
            format: .RGBAf,
            colorSpace: nil
        )
        return stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func variance(_ values: [Double]) -> Double {
        let mean = mean(values)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    /// Brightness difference across the 4px band that straddles the step:
    /// the two columns right of the edge against the two left of it.
    private static func edgeContrast(of image: CIImage) -> Double {
        let rows = CGFloat(size - 16)
        let right = mean(red(of: image, in: CGRect(x: 48, y: 8, width: 2, height: rows)))
        let left = mean(red(of: image, in: CGRect(x: 46, y: 8, width: 2, height: rows)))
        return right - left
    }

    private static let flat = CGRect(x: 8, y: 8, width: 28, height: 80)

    /// AC-16. NR Contrast hands back edge contrast the smoothing took and
    /// leaves the flat noise where Luminance put it.
    @Test func contrastKeepsEdges() {
        let frame = Self.steppedFrame()
        let without = PhotoRenderService.applyLuminanceNoiseReduction(
            amount: 0.6, detail: 0.5, contrast: 0, to: frame
        )
        let with = PhotoRenderService.applyLuminanceNoiseReduction(
            amount: 0.6, detail: 0.5, contrast: 1, to: frame
        )

        let edgeWithout = Self.edgeContrast(of: without)
        let edgeWith = Self.edgeContrast(of: with)
        #expect(edgeWith >= edgeWithout * 1.1, "edge contrast \(edgeWithout) → \(edgeWith)")

        let noiseWithout = Self.variance(Self.red(of: without, in: Self.flat))
        let noiseWith = Self.variance(Self.red(of: with, in: Self.flat))
        #expect(noiseWith <= noiseWithout * 1.2, "flat noise \(noiseWithout) → \(noiseWith)")
    }

    /// Contrast is a child of Luminance: with no smoothing there is nothing
    /// to hand back, so the frame is untouched.
    @Test func contrastDoesNothingWithoutLuminance() {
        let frame = Self.steppedFrame()
        let output = PhotoRenderService.applyLuminanceNoiseReduction(
            amount: 0, detail: 0.5, contrast: 1, to: frame
        )
        #expect(output === frame)
    }
}

private struct SplitSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
