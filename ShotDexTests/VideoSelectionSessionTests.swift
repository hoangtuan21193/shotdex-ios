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

/// ✓ and Undo (FS-12.04 §5).
@MainActor
struct VideoSessionCommitTests {
    /// A slider drag as the inspector makes it: one undo step per gesture.
    private func drag(_ model: VideoStudioModel, _ change: () -> Void) {
        model.beginUndoGroup()
        change()
        model.endUndoGroup()
    }

    /// FS-12.04 AC-4: clip 2 to 2× and to Volume 60, ✓, then Undo twice —
    /// first Volume goes back to 100 with Speed still 2×, then Speed to 1×.
    @Test func commitKeepsEachStep() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        drag(model) { model.setSpeed(2, for: clip2) }
        drag(model) { model.setClipVolume(0.6, for: clip2) }

        model.commitSession()
        #expect(model.selectedClipID == nil)
        #expect(model.session == nil)

        model.undo()
        #expect(model.recipe.clips[1].volume == 1)
        #expect(model.recipe.clips[1].speed == 2)
        model.undo()
        #expect(model.recipe.clips[1].speed == 1)
    }

    /// Undo inside a session steps as usual; one more past its start ends it
    /// and deselects.
    @Test func undoPastTheSessionStartDeselects() {
        let model = VideoStudioModelFixture.model()
        let clip1 = model.recipe.clips[0].id
        let clip2 = model.recipe.clips[1].id
        model.pushUndo()
        model.setSpeed(3, for: clip1)

        model.selectClip(clip2)
        drag(model) { model.setSpeed(2, for: clip2) }
        model.undo()
        #expect(model.recipe.clips[1].speed == 1)
        #expect(model.selectedClipID == clip2)
        #expect(model.session != nil)

        model.undo()
        #expect(model.recipe.clips[0].speed == 1)
        #expect(model.selectedClipID == nil)
        #expect(model.session == nil)
    }

    /// Selecting another item keeps what the first one changed.
    @Test func selectingAnotherItemCommitsTheFirst() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        drag(model) { model.setSpeed(2, for: clip2) }
        model.selectClip(model.recipe.clips[2].id)
        model.cancelSession()
        #expect(model.recipe.clips[1].speed == 2)
    }
}
