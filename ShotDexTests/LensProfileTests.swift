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

    @Test func profileRoundTripsInTheRecipe() throws {
        var recipe = PhotoEditRecipe()
        recipe.lensProfile = PhotoLensProfileChoice(lensID: "Nikon|Nikon AF-S Nikkor 16-35mm f/4G ED VR|1.0", cameraCropFactor: 1, isAutomatic: true)
        #expect(!recipe.isIdentity)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.lensProfile == recipe.lensProfile)
    }
}
