import Foundation
import Testing
@testable import ShotDex

/// FS-12.09 §5: the Media panel is a session — ✕ puts the project back as
/// it was when Media opened and leaves no undo step; ✓ keeps each step.
@MainActor
struct VideoStudioMediaSessionTests {
    private func sample() -> VideoStudioModel {
        let recipe = VideoStudioModelFixture.mediaSampleRecipe()
        return VideoStudioModelFixture.model(clips: recipe.clips) { $0 = recipe }
    }

    /// AC-8: Media open, two taps → ✕ → the five clips of 24.0 s, the undo
    /// history exactly as deep as when Media opened, and nothing to redo.
    @Test func cancelRestoresAndLeavesUndoDepth() {
        let model = sample()
        defer { model.close() }
        // One earlier edit, so "as deep as at open" is not just "empty".
        model.pushUndo()
        model.setPhotoDuration(4, for: model.recipe.clips[0].id)
        let before = model.recipe
        let depth = model.history.undoEntries.count
        let couldUndo = model.canUndo

        model.showToolPanel(.media)
        model.seek(to: 8.4)
        model.insertMedia([VideoMediaPick(assetID: "One", kind: .photo)])
        model.insertMedia([VideoMediaPick(assetID: "Two", kind: .photo)])
        #expect(model.recipe.clips.count == 8)
        #expect(model.sessionFooterTitle?.name == VideoStudioCopy.media)

        model.cancelSession()
        #expect(model.recipe == before)
        #expect(model.recipe.clips.count == 5)
        #expect(model.history.undoEntries.count == depth)
        #expect(model.canUndo == couldUndo)
        #expect(!model.canRedo)
        #expect(model.activeToolPanel == nil)
    }

    /// ✓ keeps each insert as its own undo step.
    @Test func commitKeepsEachStep() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.insertMedia([VideoMediaPick(assetID: "One", kind: .photo)])
        model.insertMedia([VideoMediaPick(assetID: "Two", kind: .photo)])
        model.commitSession()
        #expect(model.activeToolPanel == nil)
        #expect(model.recipe.clips.count == 7)
        model.undo()
        #expect(model.recipe.clips.count == 6)
    }
}
