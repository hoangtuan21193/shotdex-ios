import Foundation
import Testing
@testable import ShotDex

/// The selection model of the Video Studio (FS-12.04 §5): what a tap selects,
/// what ✕ and ✓ do to the project and to the undo stack.
@MainActor
struct VideoSelectionSessionTests {
    /// FS-12.04 AC-12: a locked lane refuses selection — tapping clip 2 on a
    /// locked V1 selects nothing and the bottom row stays the add tools; and
    /// locking the lane that holds the selection lets go of it.
    @Test func aLockedLaneRefusesSelection() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id

        model.toggleLaneLock(.video)
        model.toggleClip(clip2)
        #expect(model.selectedClipID == nil)
        #expect(model.inspectorTarget == .none)

        model.toggleLaneLock(.video)
        model.toggleClip(clip2)
        #expect(model.selectedClipID == clip2)
        model.toggleLaneLock(.video)
        #expect(model.selectedClipID == nil)
        #expect(model.inspectorTarget == .none)
    }
}
