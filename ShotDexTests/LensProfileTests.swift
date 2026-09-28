import CoreImage
import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-03.11 AC-14 and AC-15 — Lensfun lens profiles for JPEG.
struct LensProfileTests {
    private let matcher = LensProfileMatcher()

    @Test func theTableIsEmbedded() {
        #expect(LensProfileLibrary.shared.lenses.count > 1000)
        #expect(LensProfileLibrary.shared.cameras.count > 500)
        // Ids are unique — the picker is a ForEach over them.
        let ids = LensProfileLibrary.shared.lenses.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// FS-03.16b AC-b7 (the table side). The refreshed table carries
    /// Lensfun's vignetting (pa) and TCA as they are, and knows which Lensfun
    /// commit it came from.
    @Test func tableCarriesVignettingAndTCA() throws {
        let library = LensProfileLibrary.shared
        #expect(library.lenses.filter { !$0.vignetting.isEmpty }.count > 500)
        #expect(library.lenses.filter { !$0.tca.isEmpty }.count > 500)
        // A lens with only vignetting or TCA is kept now.
        #expect(library.lenses.contains { $0.distortion.isEmpty })

        let lens = try #require(library.lens(id: "7Artisans|7Artisans 35mm f/1.4 APS-C (manual)|1.534"))
        let first = try #require(lens.vignetting.first)
        #expect(first == LensVignettingTerm(focal: 35, aperture: 1.4, distance: 10, k1: -1.1844, k2: 0.882, k3: -0.3509))
        #expect(abs(first.falloff(at: 0) - 1) < 1e-12)
        let tca = try #require(lens.tca.first)
        #expect(tca.model == .poly3 && tca.vr == 1.000096 && tca.vb == 0.9998935)

        let url = try #require(Bundle(for: LensProfileLibrary.self).url(forResource: "lensfun-profiles", withExtension: "json"))
        let table = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect((table["lensfunCommit"] as? String)?.count == 40)
        #expect(table["lensfunDate"] as? String == "2026-09-24")
        #expect(try Data(contentsOf: url).count <= 4 * 1_048_576, "the 4 MB ceiling (16b §4)")
    }

    /// FS-03.16 AC-1. Distortion 150 · Vignetting 0 · CA 200, the switch and a
    /// Lensfun source survive encode → decode unchanged.
    @Test func strengthsSourceAndSwitchRoundTrip() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.lensDistortionScale = 1.5
        recipe.adjustments.lensVignettingScale = 0
        recipe.adjustments.lensChromaticAberrationScale = 2
        recipe.adjustments.lensCorrection = 0
        recipe.lensProfile = PhotoLensProfileChoice(
            lensID: "Canon|Canon EF 24-70mm f/2.8L II USM|1.0", cameraCropFactor: 1, isAutomatic: true
        )
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded == recipe)
        #expect(decoded.lensProfile?.vignettingSource == .lensfun)
        // Untouched strengths write no key: 100 is the profile as measured.
        let plain = String(decoding: try JSONEncoder().encode(PhotoAdjustments()), as: UTF8.self)
        #expect(!plain.contains("Scale"))
    }

    /// AC-1. A source this build does not know falls to "none" for that
    /// aspect only; the strengths and the rest of the choice stay.
    @Test func unknownSourceFallsToNoneOnly() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.lensDistortionScale = 1.5
        recipe.adjustments.lensChromaticAberrationScale = 2
        recipe.lensProfile = PhotoLensProfileChoice(
            lensID: "Canon|Canon EF 24-70mm f/2.8L II USM|1.0", cameraCropFactor: 1, isAutomatic: false
        )
        var json = String(decoding: try JSONEncoder().encode(recipe), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"vignettingSource\":\"lensfun\"", with: "\"vignettingSource\":\"neuralNet\"")
        #expect(json.contains("neuralNet"))
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: Data(json.utf8))
        let choice = try #require(decoded.lensProfile)
        #expect(choice.vignettingSource == .none)
        #expect(choice.distortionSource == .lensfun && choice.chromaticAberrationSource == .lensfun)
        #expect(choice.lensID == "Canon|Canon EF 24-70mm f/2.8L II USM|1.0" && !choice.isAutomatic)
        #expect(decoded.adjustments.lensDistortionScale == 1.5 && decoded.adjustments.lensChromaticAberrationScale == 2)
    }

    @Test func specIsReadTheWayEveryMakerWritesIt() {
        #expect(LensSpec.parse("16.0-35.0 mm f/4.0") == LensSpec(minFocal: 16, maxFocal: 35, aperture: 4))
        #expect(LensSpec.parse("EF24-70mm f/2.8L II USM") == LensSpec(minFocal: 24, maxFocal: 70, aperture: 2.8))
        #expect(LensSpec.parse("Nikon AF-S Nikkor 16-35mm f/4G ED VR") == LensSpec(minFocal: 16, maxFocal: 35, aperture: 4))
        #expect(LensSpec.parse("XF35mmF1.4 R")?.minFocal == 35)
        #expect(LensSpec.parse("Summilux-M 1:1.4/50 ASPH.") == nil)
    }

    /// AC-14. The lenses actually in the simulator library: Nikon writes
    /// only the focal range and aperture, the match finds the F-mount lens.
    @Test func nikonGenericExifFindsTheRightLens() throws {
        let wide = try #require(matcher.match(LensQuery(
            cameraMake: "NIKON CORPORATION", cameraModel: "NIKON D800E",
            lensModel: "16.0-35.0 mm f/4.0",
            spec: LensSpec(minFocal: 16, maxFocal: 35, aperture: 4),
            focal: 16, focal35: 16
        )))
        #expect(wide.lens.model == "Nikon AF-S Nikkor 16-35mm f/4G ED VR")
        #expect(wide.cameraCropFactor == 1)

        let zoom = try #require(matcher.match(LensQuery(
            cameraMake: "NIKON CORPORATION", cameraModel: "NIKON D800E",
            lensModel: "24.0-120.0 mm f/4.0",
            spec: LensSpec(minFocal: 24, maxFocal: 120, aperture: 4),
            focal: 24, focal35: 24
        )))
        #expect(zoom.lens.mounts.contains("Nikon F AF"), "not the Z-mount lens: \(zoom.lens.model)")
        #expect(zoom.lens.model.contains("24-120mm f/4"))
    }

    @Test func canonNameTokensPickTheMarkII() throws {
        let match = try #require(matcher.match(LensQuery(
            cameraMake: "Canon", cameraModel: "Canon EOS 5D Mark III",
            lensModel: "EF24-70mm f/2.8L II USM"
        )))
        #expect(match.lens.model == "Canon EF 24-70mm f/2.8L II USM")
    }

    /// AC-15 at the matcher: a body with no lens data gives no match, so the
    /// panel can say so instead of guessing.
    @Test func noLensDataMeansNoMatch() {
        #expect(matcher.match(LensQuery(cameraMake: "NIKON CORPORATION", cameraModel: "NIKON D90", focal: 26)) == nil)
        #expect(matcher.match(LensQuery(cameraMake: "Leica", lensModel: "Summilux-M 1:1.4/50 ASPH.")) == nil)
    }

    @Test func distortionInterpolatesBetweenCalibratedFocals() throws {
        let lens = try #require(LensProfileLibrary.shared.lenses.first { $0.model == "Nikon AF-S Nikkor 16-35mm f/4G ED VR" })
        #expect(LensProfileLibrary.shared.lens(id: lens.id) == lens)
        let sixteen = try #require(lens.distortion(atFocal: 16))
        let between = try #require(lens.distortion(atFocal: 17))
        #expect(sixteen.focal == lens.distortion.first?.focal)
        #expect(between.focal == 17)
        #expect(lens.distortion(atFocal: 5)?.focal == lens.distortion.first?.focal, "clamped below the range")
    }

    /// AC-14 at the pass: identity terms leave the photo alone, a real barrel
    /// correction moves the edges and never leaves empty corners.
    @Test func warpMovesEdgesAndFillsCorners() throws {
        let extent = CGRect(x: 0, y: 0, width: 300, height: 200)
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 300, y: 0),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])!.outputImage!.cropped(to: extent)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        func red(_ image: CIImage, x: Int, y: Int) -> Float {
            var pixel = [Float](repeating: 0, count: 4)
            context.render(image, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
            return pixel[0]
        }

        let identity = PhotoRenderService.applyLensProfile(
            LensDistortionTerm(model: .ptlens, focal: 16), lensCropFactor: 1, cameraCropFactor: 1, to: gradient
        )
        #expect(abs(red(identity, x: 30, y: 100) - red(gradient, x: 30, y: 100)) < 0.01)

        let barrel = LensDistortionTerm(model: .poly3, focal: 16, k1: -0.08)
        #expect(PhotoRenderService.fillZoom(barrel, extent: extent, norm: 100) >= 1)
        let corrected = PhotoRenderService.applyLensProfile(barrel, lensCropFactor: 1, cameraCropFactor: 1, to: gradient)
        #expect(abs(red(corrected, x: 150, y: 100) - red(gradient, x: 150, y: 100)) < 0.01, "centre stays put")
        #expect(abs(red(corrected, x: 20, y: 100) - red(gradient, x: 20, y: 100)) > 0.005, "edges move")
        #expect(corrected.extent == extent)
    }

    /// Hugin's convention: r = 1 is half the short side of the calibration
    /// frame. A 3:2 photo from the calibration body gets exactly its own half
    /// short side; a 4:3 photo, a larger crop body and a 4:3 calibration each
    /// move it the way the millimetres say.
    @Test func normalizationFollowsTheCalibrationFrame() {
        let threeTwo = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let same = PhotoRenderService.lensNormalizationRadius(
            extent: threeTwo, lensCropFactor: 1, cameraCropFactor: 1, calibrationAspect: 1.5
        )
        #expect(abs(same - 1000) < 0.01)

        let dx = PhotoRenderService.lensNormalizationRadius(
            extent: threeTwo, lensCropFactor: 1, cameraCropFactor: 1.5, calibrationAspect: 1.5
        )
        #expect(abs(dx - 1500) < 0.01, "a crop body sees the middle of the field")

        // 4:3 photo, 3:2 calibration, same body: same diagonal in millimetres,
        // so the radius unit follows the diagonal, not the short side.
        let fourThree = CGRect(x: 0, y: 0, width: 3000, height: 2250)
        let mixed = PhotoRenderService.lensNormalizationRadius(
            extent: fourThree, lensCropFactor: 1, cameraCropFactor: 1, calibrationAspect: 1.5
        )
        let halfDiagonal: Double = 3750 / 2          // 3000 × 2250 has a 3750 diagonal
        let calibrationDiagonal: Double = (3.25 as Double).squareRoot()
        let expected = halfDiagonal / calibrationDiagonal
        #expect(abs(mixed - expected) < 0.01)
        #expect(abs(mixed - 1125) > 50, "not simply half the 4:3 short side")
    }

    @Test func calibrationAspectIsReadFromTheTable() throws {
        let lenses = LensProfileLibrary.shared.lenses
        let fourThirds = try #require(lenses.first { $0.aspectRatio == "4:3" })
        #expect(abs(fourThirds.calibrationAspect - 4.0 / 3) < 0.001)
        let unspecified = try #require(lenses.first { $0.aspectRatio == nil })
        #expect(unspecified.calibrationAspect == 1.5)
    }

    @Test func displayNameCarriesTheMaker() throws {
        let fuji = try #require(LensProfileLibrary.shared.lenses.first { $0.model == "XF23mmF1.4 R" })
        #expect(fuji.displayName.hasPrefix(fuji.maker))
        let nikon = try #require(LensProfileLibrary.shared.lenses.first { $0.model == "Nikon AF-S Nikkor 16-35mm f/4G ED VR" })
        #expect(nikon.displayName == nikon.model, "no doubled maker")
    }

    @Test func profileRoundTripsInTheRecipe() throws {
        var recipe = PhotoEditRecipe()
        recipe.lensProfile = PhotoLensProfileChoice(lensID: "Nikon|Nikon AF-S Nikkor 16-35mm f/4G ED VR|1.0", cameraCropFactor: 1, isAutomatic: true)
        #expect(!recipe.isIdentity)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.lensProfile == recipe.lensProfile)
    }
}
