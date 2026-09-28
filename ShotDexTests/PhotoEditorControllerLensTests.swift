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
}
