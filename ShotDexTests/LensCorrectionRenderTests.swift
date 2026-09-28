import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16a §5–6 — what the lens correction passes do to pixels.
struct LensCorrectionRenderTests {

    /// A lens with strong barrel distortion, so the correction is plain.
    static let barrelID = "Canon|Canon EF 24-70mm f/2.8L II USM|1.0"

    static func jpeg() async throws -> (PhotoRenderSourceInfo, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString)")
        return (try await LensBlurTests.jpegSource(in: directory), directory)
    }

    /// AC-7. The one switch: on, a Lensfun profile corrects the JPEG; off,
    /// it renders as if there were no profile at all. The RAW half (Apple's
    /// correction off with the switch) is the decoder flag
    /// `isLensCorrectionEnabled = switch && usesAppleBuiltIn`, proven on a
    /// RAW file in the simulator.
    @Test func switchOffDisablesBuiltInAndProfile() async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lens = try #require(LensProfileLibrary.shared.lenses.first { !$0.distortion.isEmpty && $0.cropFactor == 1 })
        let renderer = PhotoRenderService()
        var on = PhotoEditRecipe.identity
        on.lensProfile = PhotoLensProfileChoice(lensID: lens.id, cameraCropFactor: 1, isAutomatic: true)
        var off = on
        off.adjustments.lensCorrection = 0
        let plain = try await renderer.render(source: source, recipe: .identity).image
        let corrected = try await renderer.render(source: source, recipe: on).image
        let switchedOff = try await renderer.render(source: source, recipe: off).image
        #expect(LensBlurTests.meanDifference(corrected, plain) > 1, "the profile should change the picture")
        #expect(LensBlurTests.meanDifference(switchedOff, plain) <= 1)
    }

    /// AC-6. The lens id is gone from the table: the render has no profile
    /// step (the photo as shot), and does not crash.
    @Test func missingLensIDRendersUncorrected() async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderer = PhotoRenderService()
        var recipe = PhotoEditRecipe.identity
        recipe.lensProfile = PhotoLensProfileChoice(lensID: "Gone|Nothing 1mm f/1|1.0", cameraCropFactor: 1, isAutomatic: true)
        recipe.adjustments.lensDistortionScale = 2
        let stale = try await renderer.render(source: source, recipe: recipe).image
        let plain = try await renderer.render(source: source, recipe: .identity).image
        #expect(LensBlurTests.meanDifference(stale, plain) <= 1)
    }

    static let barrel = LensDistortionTerm(model: .ptlens, focal: 24, a: 0.012, b: -0.035, c: 0.01)
    static let fringe = LensTCATerm(model: .poly3, focal: 24, br: 0.0004, cr: 0, vr: 1.0006, bb: -0.0003, cb: 0, vb: 0.9995)

    /// A flat grey frame in linear light, as the first pass after decode sees it.
    static func flatGrey(width: Int = 600, height: Int = 400) -> CIImage {
        CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func linearValue(_ image: CIImage, at point: CGPoint) -> Double {
        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return Double(pixel[1])
    }

    /// 16a AC-a8. At 200 the distortion moves each point twice as far as at
    /// 100, the red/blue offset doubles, and the vignetting gain squares.
    @Test func twoHundredDoublesDisplacementSquaresGainDoublesCA() {
        func table(_ s: Double) -> LensCorrectionTable {
            .make(distortion: Self.barrel, tca: Self.fringe, distortionStrength: s,
                  chromaticAberrationStrength: s, maximumRadius: 2)
        }
        let one = table(1), two = table(2)
        for r in [0.4, 0.9, 1.3, 1.8] {
            let a = one.scales(at: r), b = two.scales(at: r)
            // Displacement in pixels at a 2000px normalisation radius.
            let d1 = (a.green - 1) * r * 2000, d2 = (b.green - 1) * r * 2000
            #expect(abs(d2 - 2 * d1) <= 0.5, "r \(r): \(d1) → \(d2) px")
            let ca1 = a.red / a.green - 1, ca2 = b.red / b.green - 1
            #expect(abs(ca2 - 2 * ca1) <= abs(ca1) * 0.01 + 1e-7, "red offset r \(r)")
            let cb1 = a.blue / a.green - 1, cb2 = b.blue / b.green - 1
            #expect(abs(cb2 - 2 * cb1) <= abs(cb1) * 0.01 + 1e-7, "blue offset r \(r)")
        }

        let term = LensVignettingTerm(focal: 24, aperture: 2.8, distance: 10, k1: -0.45, k2: 0.1, k3: -0.02)
        func gain(_ s: Double) -> Double {
            let image = LensCorrectionPass.applyVignetting(
                term, strength: s, lensCropFactor: 1, cameraCropFactor: 1, calibrationAspect: 1.5, to: Self.flatGrey()
            )
            return Self.linearValue(image, at: CGPoint(x: 2, y: 2)) / Self.linearValue(image, at: CGPoint(x: 300, y: 200))
        }
        let g1 = gain(1), g2 = gain(2)
        #expect(g1 > 1.05, "the corner is brightened")
        #expect(abs(g2 - g1 * g1) <= g1 * g1 * 0.01, "gain² — \(g1) → \(g2)")
    }

    /// A real Lensfun row with distortion, vignetting and TCA.
    static func fullLens() throws -> LensfunLens {
        try #require(LensProfileLibrary.shared.lenses.first {
            !$0.distortion.isEmpty && !$0.vignetting.isEmpty && !$0.tca.isEmpty && $0.cropFactor == 1
        })
    }

    /// 16a AC-a7. All three strengths at 0: the photo exactly as with the
    /// switch off — no warp, fill zoom 1.0, no vignetting gain.
    @Test func zeroStrengthsMatchSwitchOff() async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lens = try Self.fullLens()
        var zero = PhotoEditRecipe.identity
        zero.lensProfile = PhotoLensProfileChoice(lensID: lens.id, cameraCropFactor: 1, isAutomatic: true)
        for kind in [PhotoAdjustmentKind.lensDistortionScale, .lensVignettingScale, .lensChromaticAberrationScale] {
            zero.adjustments[kind] = 0
        }
        var off = zero
        off.adjustments.lensCorrection = 0
        let renderer = PhotoRenderService()
        let a = try await renderer.render(source: source, recipe: zero).image
        let b = try await renderer.render(source: source, recipe: off).image
        #expect(LensBlurTests.meanDifference(a, b) <= 1)

        let flat = LensCorrectionTable.make(
            distortion: Self.barrel, tca: Self.fringe, distortionStrength: 0,
            chromaticAberrationStrength: 0, maximumRadius: 2
        )
        #expect(flat.isIdentity)
        #expect(LensCorrectionPass.fillZoom(flat, extent: CGRect(x: 0, y: 0, width: 600, height: 400), norm: 200) == 1)
    }

    /// 16a AC-a18. Distortion and CA are one pass in the render graph — one
    /// lensCorrect node, no lensWarp beside it.
    @Test func distortionAndCAShareOnePass() throws {
        let image = LensCorrectionPass.apply(
            distortion: Self.barrel, tca: Self.fringe, distortionStrength: 1, chromaticAberrationStrength: 1,
            lensCropFactor: 1, cameraCropFactor: 1, calibrationAspect: 1.5, manualDistortion: 0.3,
            to: Self.flatGrey()
        )
        let graph = image.debugDescription
        #expect(graph.components(separatedBy: "lensCorrect").count - 1 == 1, "\(graph)")
        #expect(!graph.contains("lensWarp"))
    }

    /// 16a AC-a17. Remove CA is not the profile: with the profile's CA at 0
    /// and at 200, turning the chip on still changes the picture.
    @Test(arguments: [0.0, 2.0])
    func removeCAChipChangesImageAtBothCAStrengths(_ strength: Double) async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lens = try Self.fullLens()
        var chipOff = PhotoEditRecipe.identity
        chipOff.lensProfile = PhotoLensProfileChoice(lensID: lens.id, cameraCropFactor: 1, isAutomatic: true)
        chipOff.adjustments.lensChromaticAberrationScale = strength
        var chipOn = chipOff
        chipOn.adjustments.chromaticAberration = 1
        let renderer = PhotoRenderService()
        let a = try await renderer.render(source: source, recipe: chipOff).image
        let b = try await renderer.render(source: source, recipe: chipOn).image
        #expect(LensBlurTests.meanDifference(a, b) > 0.5, "CA \(strength)")
    }

    /// 16a AC-a3. The RAW decoder's linear-slot filter lifts a flat grey
    /// frame exactly as Lensfun's pa model says: corner/centre =
    /// 1 / (1 + k1 r² + k2 r⁴ + k3 r⁶), r = 1 at the calibration frame's
    /// corner, within 1/255.
    @Test func vignetteGainMatchesPAModel() throws {
        let term = LensVignettingTerm(focal: 24, aperture: 2.8, distance: 10, k1: -0.45, k2: 0.1, k3: -0.02)
        let filter = LensVignetteFilter()
        filter.term = term
        filter.inputImage = Self.flatGrey()
        let output = try #require(filter.outputImage)
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let norm = PhotoRenderService.lensNormalizationRadius(
            extent: extent, lensCropFactor: 1, cameraCropFactor: 1, calibrationAspect: 1.5
        ) * (1 + 1.5 * 1.5).squareRoot()
        let corner = CGPoint(x: 2, y: 2)
        let r = hypot(corner.x + 0.5 - 300, corner.y + 0.5 - 200) / norm
        let r2 = r * r
        let expected = 0.25 / (1 + term.k1 * r2 + term.k2 * r2 * r2 + term.k3 * r2 * r2 * r2)
        #expect(abs(Self.linearValue(output, at: corner) - expected) <= 1.0 / 255, "\(Self.linearValue(output, at: corner)) vs \(expected)")
        #expect(abs(Self.linearValue(output, at: CGPoint(x: 300, y: 200)) - 0.25) <= 1.0 / 255)
    }
}
