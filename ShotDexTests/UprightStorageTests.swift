import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15b AC-27 — Upright is stored as a mode plus a solved transform,
/// apart from the Geometry sliders.
struct UprightStorageTests {

    /// AC-27. A solved Upright pass and a hand-set Vertical 10 live side by
    /// side; the render reads the stored transform and never solves again;
    /// Off hands back exactly Vertical 10.
    @MainActor @Test func solvedTransformAndSlidersAreSeparate() {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.storeUpright(UprightSuggestion(rotate: 0.05, vertical: -0.3), mode: .full)
        controller.setAdjustment(.geoVertical, value: 0.1)

        #expect(controller.recipe.upright.mode == .full)
        #expect(controller.recipe.upright.solved.vertical == -0.3)
        #expect(controller.recipe.upright.solved.rotate == 0.05)
        #expect(controller.recipe.adjustments.geoVertical == 0.1, "the slider is its own value")

        let before = controller.uprightSolveCount
        for _ in 0..<20 { controller.scheduleRender() }
        #expect(controller.uprightSolveCount == before, "a render must not solve Upright again")

        controller.resetUpright()
        #expect(controller.recipe.upright.isIdentity)
        #expect(controller.recipe.adjustments.geoVertical == 0.1)
        #expect(controller.recipe.adjustments.geoRotate == 0)
    }

    /// The render adds the solved transform to the sliders, and reads only
    /// what is stored: a recipe that names a mode but holds no solved
    /// transform renders as though Upright were off — nothing is solved on
    /// the way through.
    @Test func renderAddsTheStoredTransformAndSolvesNothing() throws {
        let input = KernelGolden.image(try KernelGolden.photo(phase: 0))

        var sliders = PhotoAdjustments()
        sliders.geoVertical = 0.1
        var solved = PhotoUprightTransform.identity
        solved.vertical = -0.3
        var combined = PhotoAdjustments()
        combined.geoVertical = 0.1 - 0.3

        let stacked = PhotoRenderService.applyGeo(sliders, upright: solved, to: input)
        let direct = PhotoRenderService.applyGeo(combined, to: input)
        #expect(Self.largestDifference(stacked, direct) < 1e-4)

        let modeOnly = PhotoRenderService.applyGeo(sliders, upright: .identity, to: input)
        let slidersOnly = PhotoRenderService.applyGeo(sliders, to: input)
        #expect(Self.largestDifference(modeOnly, slidersOnly) == 0)
    }

    private static func largestDifference(_ a: CIImage, _ b: CIImage) -> Float {
        zip(KernelGolden.pixels(of: a), KernelGolden.pixels(of: b)).map { abs($0 - $1) }.max() ?? 1
    }
}
