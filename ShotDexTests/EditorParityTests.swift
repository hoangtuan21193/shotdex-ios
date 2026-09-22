import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.11 — the six things ShotDex is catching up with Lightroom on.
struct EditorParityTests {

    /// The word "AI" as a whole word, in any case.
    private func mentionsAI(_ text: String) -> Bool {
        text.range(of: #"(?i)\bAI\b"#, options: .regularExpression) != nil
    }

    /// AC-16. Noise reduction here is a tuned classic filter, not a model, and
    /// the interface must not say otherwise: nothing a photographer reads next
    /// to a noise slider may claim "AI".
    @Test func noiseReductionNeverClaimsToBeAI() {
        let groups = EditorAdjustmentCatalog.groups(isRAWSource: true, scope: .global, hasDepth: true)
        let detailKinds = groups
            .filter { $0.id == .detail || $0.id == .raw }
            .flatMap(\.kinds)
        #expect(!detailKinds.isEmpty)
        for kind in detailKinds {
            #expect(!mentionsAI(EditorAdjustmentCatalog.shortTitle(of: kind)), "short title of \(kind)")
            #expect(!mentionsAI(kind.displayName), "display name of \(kind)")
        }
        for group in groups where group.id == .detail || group.id == .raw {
            #expect(!mentionsAI(group.title))
        }
    }
}

/// FS-03.11 AC-13 — noise comes out before anything sharpens it.
struct DetailPassOrderTests {
    @Test func noiseReductionRunsBeforeEverySharpeningPass() throws {
        let order = PhotoRenderService.detailPassOrder
        #expect(Set(order) == Set(PhotoRenderService.DetailPass.allCases), "every pass runs once")
        #expect(order.count == PhotoRenderService.DetailPass.allCases.count)
        let noise = try #require(order.firstIndex(of: .noiseReduction))
        for pass in [PhotoRenderService.DetailPass.sharpen, .definition, .texture, .clarity] {
            let index = try #require(order.firstIndex(of: pass))
            #expect(noise < index, "noise reduction must run before \(pass)")
        }
    }
}

/// FS-03.11 AC-12 — Luminance · Detail · Color, and Detail keeping texture.
struct NoiseReductionSplitTests {
    @Test func noiseReductionIsThreeOneWaySliders() {
        let detail = EditorAdjustmentCatalog
            .groups(isRAWSource: false, scope: .global)
            .first { $0.id == .detail }?.kinds ?? []
        let noise = detail.filter {
            [.noiseReduction, .noiseDetail, .colorNoiseReduction].contains($0)
        }
        #expect(noise == [.noiseReduction, .noiseDetail, .colorNoiseReduction])
        for kind in noise {
            #expect(!EditorAdjustmentCatalog.isBipolar(kind), "\(kind) is a strength")
            #expect(EditorAdjustmentCatalog.sliderRange(of: kind) == 0...1)
        }
        // Detail waits for Luminance, like grain size waits for grain.
        #expect(EditorAdjustmentCatalog.parentKind(of: .noiseDetail) == .noiseReduction)
        #expect(PhotoAdjustments().noiseDetail == 0.5)
        #expect(PhotoAdjustments().isIdentity)
        // A one-way strength reads "50", not "+50".
        #expect(EditorAdjustmentCatalog.displayText(0.5, of: .noiseDetail) == "50")
        #expect(EditorAdjustmentCatalog.displayText(0.3, of: .grain) == "30")
        #expect(EditorAdjustmentCatalog.displayText(0.12, of: .shadows) == "+12")
    }

    /// Synthetic ISO-6400 stand-in: left half flat grey with per-pixel noise,
    /// right half a coarse ±0.12 texture (a 6-pixel checker, like pores at this
    /// scale) under the same noise. Local variance is measured on each half.
    private func noisyFrame(size: Int = 96) -> CIImage {
        var generator = SeededGenerator(seed: 6400)
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let noise = Float.random(in: -0.08...0.08, using: &generator)
                var value: Float = 0.5 + noise
                if x >= size / 2 {
                    value += ((x / 6 + y / 6) % 2 == 0) ? 0.12 : -0.12
                }
                let index = (y * size + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
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

    /// Variance of red over a rectangle, away from the image edges.
    private func variance(of image: CIImage, in rect: CGRect) -> Double {
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
        let values = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    @Test func luminanceSixtyDetailFiftyCutsNoiseAndKeepsTexture() {
        let frame = noisyFrame()
        let flat = CGRect(x: 8, y: 8, width: 32, height: 80)
        let textured = CGRect(x: 56, y: 8, width: 32, height: 80)

        let cleaned = PhotoRenderService.applyLuminanceNoiseReduction(
            amount: 0.6,
            detail: 0.5,
            to: frame
        )
        let noiseBefore = variance(of: frame, in: flat)
        let noiseAfter = variance(of: cleaned, in: flat)
        let textureBefore = variance(of: frame, in: textured)
        let textureAfter = variance(of: cleaned, in: textured)

        #expect(noiseAfter < noiseBefore * 0.25, "grain measurably reduced: \(noiseBefore) → \(noiseAfter)")
        #expect(textureAfter > textureBefore * 0.6, "texture not wiped: \(textureBefore) → \(textureAfter)")
    }

    @Test func moreDetailKeepsMoreTexture() {
        let frame = noisyFrame()
        let textured = CGRect(x: 56, y: 8, width: 32, height: 80)
        let smooth = PhotoRenderService.applyLuminanceNoiseReduction(amount: 0.6, detail: 0, to: frame)
        let crisp = PhotoRenderService.applyLuminanceNoiseReduction(amount: 0.6, detail: 1, to: frame)
        #expect(variance(of: crisp, in: textured) > variance(of: smooth, in: textured))
    }
}

/// Deterministic noise for the synthetic frame.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
