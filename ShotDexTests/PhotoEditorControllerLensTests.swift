import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16 — the editor's side of lens correction.
@MainActor
struct PhotoEditorControllerLensTests {

    private func makeController() -> PhotoEditorController {
        PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
    }

    /// AC-2. Distortion 100 dragged to 160 and let go is one history step;
    /// Undo puts 100 back — the same recipe, so the same render.
    @Test func distortionDragRecordsOneStep() {
        let controller = makeController()
        let before = controller.recipe
        controller.beginContinuousChange()
        for step in 1...12 {
            controller.setAdjustment(.lensDistortionScale, value: 1 + Double(step) * 0.05)
        }
        controller.endContinuousChange()
        #expect(abs(controller.recipe.adjustments.lensDistortionScale - 1.6) < 1e-9)
        #expect(controller.historyTimeline.count == 2)
        controller.undo()
        #expect(controller.recipe == before)
        #expect(controller.recipe.adjustments.lensDistortionScale == 1)
    }

    /// AC-6. A recipe pointing at a lens the refreshed table no longer has:
    /// the panel says "No profile for this lens yet", nothing is guessed.
    @Test func staleLensIDIsNoProfile() {
        let controller = makeController()
        controller.recipe.lensProfile = PhotoLensProfileChoice(
            lensID: "Sony|E PZ 16-50mm f/3.5-5.6 OSS|1.534", cameraCropFactor: 1.534, isAutomatic: true
        )
        #expect(LensProfileLibrary.shared.lens(id: "Sony|E PZ 16-50mm f/3.5-5.6 OSS|1.534") == nil)
        let resolution = controller.lensCorrectionResolution
        #expect(resolution.panel == .noProfile)
        #expect(resolution.liveAspects.isEmpty)
    }

    /// E19. A RAW whose lens source was resolved on open, closed untouched:
    /// the recipe is still identity (no dot, no save prompt).
    @Test func rawOpenedWithoutEditsStaysIdentity() {
        let controller = makeController()
        controller.sessionLensChoice = PhotoLensProfileChoice(
            lensID: nil, cameraCropFactor: 1, isAutomatic: true,
            distortionSource: .appleBuiltIn, vignettingSource: .appleBuiltIn, chromaticAberrationSource: .appleBuiltIn
        )
        #expect(controller.recipe.isIdentity)
        #expect(controller.recipe.lensProfile == nil)
    }

    /// E19. The first edit writes the resolved source; one Undo takes the
    /// edit and the source back off together.
    @Test func firstEditWritesResolvedSource() {
        let controller = makeController()
        let session = PhotoLensProfileChoice(lensID: "Canon|Canon EF 24-70mm f/2.8L II USM|1.0", cameraCropFactor: 1, isAutomatic: true)
        controller.sessionLensChoice = session
        controller.setAdjustment(.exposure, value: 0.3)
        #expect(controller.recipe.lensProfile == session)
        controller.undo()
        #expect(controller.recipe.lensProfile == nil && controller.recipe.isIdentity)
    }

    /// 16b AC-b3. Change → a lens picked by hand reads "Chosen by you", in
    /// one step; one Undo puts back what was there.
    @Test func chooseLensIsOneStep() throws {
        let controller = makeController()
        let lens = try #require(LensProfileLibrary.shared.lenses.first { !$0.distortion.isEmpty })
        let before = controller.recipe
        controller.chooseLensProfile(lens)
        #expect(controller.historyTimeline.count == 2)
        #expect(controller.lensCorrectionResolution.panel == .chosen(lensName: lens.displayName))
        #expect(controller.isLensCorrectionOn)
        controller.undo()
        #expect(controller.recipe == before)
    }

    /// 16b AC-b4, AC-b10, AC-b11 — the strengths are dead when nothing but
    /// Apple, or nothing at all, corrects the photo.
    @Test func strengthSlidersFollowTheLiveAspects() {
        let controller = makeController()
        #expect(!controller.isLensStrengthLive(.lensDistortionScale), "no lens: dim")
        #expect(controller.isLensStrengthLive(.exposure), "other rows untouched")
        #expect(!controller.hasEmbeddedLensData, "a JPEG never offers the file's data (AC-b11)")
    }
}
