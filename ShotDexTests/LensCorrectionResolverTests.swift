import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16 §3 and 16a §6 — which source corrects each aspect.
struct LensCorrectionResolverTests {

    static func lens(distortion: Bool = true, vignetting: Bool = true, tca: Bool = true) -> LensfunLens {
        LensfunLens(
            maker: "Canon", model: "Canon EF 24-70mm f/2.8L II USM", aliases: [], mounts: ["Canon EF"], cropFactor: 1,
            distortion: distortion ? [LensDistortionTerm(model: .ptlens, focal: 24, a: 0.01, b: -0.03, c: 0)] : [],
            vignetting: vignetting ? [LensVignettingTerm(focal: 24, aperture: 2.8, distance: 10, k1: -0.5, k2: 0.2, k3: -0.05)] : [],
            tca: tca ? [LensTCATerm(model: .poly3, focal: 24, vr: 1.0003, vb: 0.9998)] : []
        )
    }

    /// 16a AC-a11. An iPhone HEIC — no maker data, no Lensfun row — is
    /// source 4: every aspect none, Apple's correction off, no live slider;
    /// and it renders exactly as with the switch off.
    @Test func iPhoneHEICResolvesToNone() async throws {
        let resolution = LensCorrectionResolver.resolve(LensCorrectionInputs(isRAW: false))
        #expect(resolution.panel == .noProfile)
        #expect(resolution.choice.distortionSource == .none && resolution.choice.vignettingSource == .none
            && resolution.choice.chromaticAberrationSource == .none)
        #expect(!resolution.usesAppleBuiltIn && resolution.liveAspects.isEmpty)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await LensBlurTests.jpegSource(in: directory)
        let renderer = PhotoRenderService()
        var on = PhotoEditRecipe.identity
        on.lensProfile = resolution.choice
        on.adjustments.lensDistortionScale = 2
        var off = on
        off.adjustments.lensCorrection = 0
        let a = try await renderer.render(source: source, recipe: on).image
        let b = try await renderer.render(source: source, recipe: off).image
        #expect(LensBlurTests.meanDifference(a, b) <= 1)
    }

    /// 16a AC-a5. A RAW from a body neither the file nor Lensfun covers, but
    /// the decoder can correct: source 3 — Apple's correction, sliders dead,
    /// and the strengths change nothing.
    @Test func unsupportedMakerWithDecoderSupportIsBuiltIn() async throws {
        let resolution = LensCorrectionResolver.resolve(
            LensCorrectionInputs(isRAW: true, decoderSupportsLensCorrection: true)
        )
        #expect(resolution.panel == .builtIn)
        #expect(resolution.usesAppleBuiltIn && resolution.liveAspects.isEmpty)
        #expect(resolution.choice.lensID == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await LensBlurTests.jpegSource(in: directory)
        let renderer = PhotoRenderService()
        var zero = PhotoEditRecipe.identity
        zero.lensProfile = resolution.choice
        for kind in [PhotoAdjustmentKind.lensDistortionScale, .lensVignettingScale, .lensChromaticAberrationScale] {
            zero.adjustments[kind] = 0
        }
        var full = zero
        for kind in [PhotoAdjustmentKind.lensDistortionScale, .lensVignettingScale, .lensChromaticAberrationScale] {
            full.adjustments[kind] = 2
        }
        let a = try await renderer.render(source: source, recipe: zero).image
        let b = try await renderer.render(source: source, recipe: full).image
        #expect(LensBlurTests.meanDifference(a, b) <= 1)
    }

    /// 16a AC-a6. The decoder cannot correct this body either: source 4.
    @Test func noDecoderSupportIsNone() {
        let resolution = LensCorrectionResolver.resolve(
            LensCorrectionInputs(isRAW: true, decoderSupportsLensCorrection: false)
        )
        #expect(resolution.panel == .noProfile)
        #expect(!resolution.usesAppleBuiltIn)
    }

    /// Per aspect, never twice: the file's data first, Lensfun fills what
    /// the file lacks, and any profile turns Apple's correction off.
    @Test func eachAspectTakesTheBestSourceAndAppleStaysOff() {
        let resolution = LensCorrectionResolver.resolve(LensCorrectionInputs(
            isRAW: true,
            embeddedAspects: [.distortion],
            embeddedLensName: "FE 24-70mm F2.8 GM II",
            lensfunLens: Self.lens(tca: false),
            decoderSupportsLensCorrection: true
        ))
        #expect(resolution.choice.distortionSource == .embedded)
        #expect(resolution.choice.vignettingSource == .lensfun)
        #expect(resolution.choice.chromaticAberrationSource == .none)
        #expect(!resolution.usesAppleBuiltIn)
        #expect(resolution.panel == .found(lensName: "FE 24-70mm F2.8 GM II"))
        #expect(resolution.liveAspects == [.distortion, .vignetting])
    }

    /// A JPEG the camera corrected is not matched again; a lens chosen by
    /// hand still runs.
    @Test func correctedInCameraSkipsTheMatchUnlessChosen() {
        var inputs = LensCorrectionInputs(isRAW: false, lensfunLens: Self.lens(), isJPEGCorrectedInCamera: true)
        #expect(LensCorrectionResolver.resolve(inputs).panel == .correctedInCamera)
        inputs.lensfunChosenByUser = true
        let chosen = LensCorrectionResolver.resolve(inputs)
        #expect(chosen.panel == .chosen(lensName: "Canon EF 24-70mm f/2.8L II USM"))
        #expect(chosen.choice.distortionSource == .lensfun)
    }
}
