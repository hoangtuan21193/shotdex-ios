import CoreImage
import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-12.06c §5, AC-1: a look's per-pixel stages baked into a 33³ table
/// render the frame the photo editor's own chain renders.
struct VideoLookBakerTests {
    private let context = CIContext()

    /// 64×64 of colours spread over the cube, not a flat card — the same
    /// frame `LookExportCubeTests` checks the `.cube` export on.
    static func testFrame() -> CIImage {
        let side = 64
        var values = [Float](repeating: 1, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                values[i] = Float(x) / Float(side - 1)
                values[i + 1] = Float(y) / Float(side - 1)
                values[i + 2] = Float((x * 7 + y * 13) % side) / Float(side - 1)
            }
        }
        return CIImage(
            bitmapData: values.withUnsafeBytes { Data($0) },
            bytesPerRow: side * 16,
            size: CGSize(width: side, height: side),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }

    /// The editor's chain on the frame: every pre-mask stage of `look`.
    static func editorChain(_ look: PhotoEditRecipe, on frame: CIImage) -> CIImage {
        let source = PhotoRenderSourceInfo(
            url: URL(fileURLWithPath: "/dev/null"), type: .png,
            pixelWidth: Int(frame.extent.width), pixelHeight: Int(frame.extent.height),
            orientation: .up, isRAW: false, properties: [:]
        )
        var recipe = look
        recipe.adjustments.lensCorrection = 0
        return PhotoRenderService.applyPreMaskStages(of: recipe, source: source, appliesExposure: true, to: frame)
            .cropped(to: frame.extent)
    }

    private func meanError(_ a: CIImage, _ b: CIImage) -> Float {
        let side = 64
        func pixels(_ image: CIImage) -> [Float] {
            var out = [Float](repeating: 0, count: side * side * 4)
            out.withUnsafeMutableBytes {
                context.render(
                    image, toBitmap: $0.baseAddress!, rowBytes: side * 16,
                    bounds: CGRect(x: 0, y: 0, width: side, height: side),
                    format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                )
            }
            // Bytes, as the frame is written: values past white are white.
            return stride(from: 0, to: out.count, by: 4).flatMap { out[$0..<$0 + 3] }.map { min(1, max(0, $0)) }
        }
        let a = pixels(a), b = pixels(b)
        return zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Float(a.count)
    }

    /// Tone, HSL, a curve and Velvia — a look with something in every
    /// per-pixel stage.
    static var toneHSLCurveVelvia: PhotoEditRecipe {
        var look = PhotoEditRecipe.identity
        look.adjustments.exposure = 0.3
        look.adjustments.contrast = 0.2
        look.adjustments.highlights = -0.3
        look.adjustments.warmth = 0.15
        look.color.mixer.blue.saturation = -0.4
        look.color.mixer.orange.hue = 0.2
        look.curve.rgb = [CurvePoint(x: 0, y: 0.04), CurvePoint(x: 0.5, y: 0.55), CurvePoint(x: 1, y: 0.96)]
        look.filter = .velvia
        return look
    }

    /// AC-1: on the 64×64 frame the baked table lands within 1/255 on
    /// average of the editor's chain.
    @Test func tableMatchesEditorChain() throws {
        let look = Self.toneHSLCurveVelvia
        #expect(VideoLookBaker.parts(of: look) == [.whole])
        let table = try #require(VideoLookBaker.bake(.whole, of: look, context: context))
        #expect(table.dimension == 33)
        let frame = Self.testFrame()
        let error = meanError(
            PhotoRenderService.applyLUT(table, intensity: 1, to: frame),
            Self.editorChain(look, on: frame)
        )
        #expect(error <= 1.0 / 255, "mean error \(error * 255)/255")
    }

    /// Brilliance is per pixel (its highlight/shadow pass has no radius), so
    /// a video table carries it — unlike the `.cube` export, which still
    /// lists it as lost.
    @Test func brillianceIsBaked() throws {
        var look = PhotoEditRecipe.identity
        look.adjustments.brilliance = 0.6
        let table = try #require(VideoLookBaker.bake(.whole, of: look, context: context))
        let frame = Self.testFrame()
        let baked = PhotoRenderService.applyLUT(table, intensity: 1, to: frame)
        let error = meanError(baked, Self.editorChain(look, on: frame))
        #expect(error <= 1.0 / 255, "mean error \(error * 255)/255")
        // And it did something: the frame is not the identity table's.
        #expect(meanError(baked, frame) > 3.0 / 255)
    }

    /// A look with Clarity splits at the neighbourhood stages: Light before,
    /// Color after — and the two tables, run back to back with nothing
    /// between, are the editor's Light stages, then its Color stages. The
    /// frame is clipped to 0…1 between the two (a table's domain), which is
    /// the one thing a split look gives up against the photo.
    @Test func neighbourStagesSplitTheTableInTwo() throws {
        var look = Self.toneHSLCurveVelvia
        look.adjustments.clarity = 0.3
        look.adjustments.brilliance = 0.2
        #expect(VideoLookBaker.parts(of: look) == [.light, .colour])
        let light = try #require(VideoLookBaker.bake(.light, of: look, context: context))
        let colour = try #require(VideoLookBaker.bake(.colour, of: look, context: context))
        let frame = Self.testFrame()
        let split = PhotoRenderService.applyLUT(colour, intensity: 1, to: PhotoRenderService.applyLUT(light, intensity: 1, to: frame))
        let lit = Self.editorChain(VideoLookBaker.recipe(.light, of: look), on: frame)
            .applyingFilter("CIColorClamp")
        let expected = Self.editorChain(VideoLookBaker.recipe(.colour, of: look), on: lit)
        let error = meanError(split, expected)
        #expect(error <= 1.5 / 255, "mean error \(error * 255)/255")
        // The light half carries no film look; the colour half no exposure.
        #expect(VideoLookBaker.recipe(.light, of: look).filter == .original)
        #expect(VideoLookBaker.recipe(.colour, of: look).adjustments.exposure == 0)
        #expect(VideoLookBaker.recipe(.colour, of: look).adjustments.brilliance == 0)
    }

    /// The bake's cost on this machine, logged for the plan's measurement
    /// (§9: target ≤ 50 ms a look on an iPhone 17; the simulator is only a
    /// signal). Ten looks: film looks, a tone look, and a two-table look.
    @Test func bakeTimeIsLogged() throws {
        var looks: [PhotoEditRecipe] = [PhotoFilter.velvia, .classicChrome, .portra400, .acros, .leicaTeal, .mono].map {
            var look = PhotoEditRecipe.identity
            look.filter = $0
            return look
        }
        looks.append(Self.toneHSLCurveVelvia)
        var clarity = Self.toneHSLCurveVelvia
        clarity.adjustments.clarity = 0.3
        looks.append(clarity)
        var brilliance = PhotoEditRecipe.identity
        brilliance.adjustments.brilliance = 0.5
        looks.append(brilliance)
        var calibrated = PhotoEditRecipe.identity
        calibrated.color.calibration.redHue = 0.3
        looks.append(calibrated)
        // One warm-up: the first render compiles Core Image's kernels.
        _ = VideoLookBaker.bake(.whole, of: looks[0], context: context)
        var times: [Double] = []
        for look in looks {
            let start = Date()
            for part in VideoLookBaker.parts(of: look) {
                #expect(VideoLookBaker.bake(part, of: look, context: context) != nil)
            }
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        print("[video-look] bake ms: \(times.map { String(format: "%.1f", $0) }.joined(separator: ", ")); max \(String(format: "%.1f", times.max() ?? 0))")
        #expect(times.count == 10)
    }
}
