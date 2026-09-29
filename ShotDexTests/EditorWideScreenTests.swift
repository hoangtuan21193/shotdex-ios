import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.09 — the recipe side of the wide-screen panel's reset and cancel
/// controls. The panel calls exactly these controller methods (`resetSection`,
/// `resetStageMode` and `cancelStageMode` in `PhotoEditorScreen`), so what one
/// history step and "nothing left behind" mean is decided here, not in a view.
@MainActor
struct EditorWideScreenTests {

    private func makeController() -> PhotoEditorController {
        PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
    }

    /// The kinds the Light card's ↺ resets: the catalog's Light group, which is
    /// what `catalogGroups(for: .light)` hands `resetSection`.
    private var lightKinds: [PhotoAdjustmentKind] {
        EditorAdjustmentCatalog.groups(isRAWSource: false, scope: .global)
            .first { $0.id == .light }?.kinds ?? []
    }

    /// AC-26. ↺ on Light puts Light back and nothing else, in one Undo step.
    @Test func resettingLightLeavesTheOtherCardsAloneInOneStep() {
        let controller = makeController()
        controller.setAdjustment(.saturation, value: 0.3)
        controller.setAdjustment(.vignette, value: -0.2)
        controller.setAdjustment(.exposure, value: 0.5)
        controller.setAdjustment(.shadows, value: 0.25)
        let edited = controller.recipe

        controller.resetAdjustments(lightKinds)

        for kind in lightKinds {
            #expect(controller.recipe.adjustments[kind] == PhotoAdjustments()[kind])
        }
        #expect(controller.recipe.adjustments.saturation == 0.3)
        #expect(controller.recipe.adjustments.vignette == -0.2)

        // One step: a single Undo brings every Light value back at once.
        controller.undo()
        #expect(controller.recipe == edited)
    }

    /// AC-29, the history half. Three layers off in one step, and one Undo
    /// brings all three back. (The confirmation the AC also asks for is not in
    /// the code — see the verify report.)
    @Test func removingEveryLayerIsOneUndoStep() {
        let controller = makeController()
        controller.addShapeOverlay(.rectangle)
        controller.addShapeOverlay(.oval)
        controller.addShapeOverlay(.arrow)
        #expect(controller.recipe.overlays.count == 3)
        let withLayers = controller.recipe.overlays

        controller.removeAllOverlays()
        #expect(controller.recipe.overlays.isEmpty)

        controller.undo()
        #expect(controller.recipe.overlays == withLayers)
    }

    /// AC-35. Cancel in Crop & Geometry: the frame goes back to what the mode
    /// opened on, and the history holds no crop step — Undo has nothing to do.
    @Test func cancellingCropLeavesNoStepBehind() {
        let controller = makeController()
        #expect(!controller.canUndo)

        // The screen's path into the mode: the tool switch opens the crop
        // session, `selectGroup` opens the stage session.
        controller.selectedTool = .crop
        controller.beginStageSession()
        controller.rotate()
        controller.chooseCropAspect(.square, imageAspect: 1.5)
        #expect(controller.recipe.crop != .identity)

        // `cancelStageMode(.crop)`: cancel the crop session, then go back to
        // Edit, which drops the stage entry.
        controller.cancelCropSession()
        controller.clearStageEntry()
        controller.selectedTool = .adjust

        #expect(controller.recipe.crop == .identity)
        #expect(!controller.canUndo)
        #expect(controller.historyTimeline.count == 1)
    }

    /// AC-13's leave-without-applying rule is the crop session's: switching
    /// the tool away without `commitCropSession` puts the frame back.
    @Test func leavingCropWithoutApplyingDropsTheFrame() {
        let controller = makeController()
        controller.selectedTool = .crop
        controller.rotate()
        #expect(controller.recipe.crop.quarterTurns == 1)
        controller.selectedTool = .adjust
        #expect(controller.recipe.crop == .identity)
    }
}
