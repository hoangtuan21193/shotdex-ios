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

extension VideoStudioMediaSessionTests {
    /// AC-2: Select, pick three, Add (3) → three clips after the cut at
    /// 8.4 in the order picked (1-2-3), one undo back to the five clips.
    /// Unpicking renumbers; Select again drops every pick.
    @Test func addThreeInSelectionOrderOneUndo() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.seek(to: 8.4)
        model.toggleMediaSelecting()
        for id in ["C", "X", "A", "B"] { model.toggleMediaPick(VideoMediaPick(assetID: id, kind: .photo)) }
        model.toggleMediaPick(VideoMediaPick(assetID: "X", kind: .photo))
        #expect(model.mediaPickNumber("C") == 1)
        #expect(model.mediaPickNumber("A") == 2)
        #expect(model.mediaPickNumber("B") == 3)
        #expect(model.mediaPickNumber("X") == nil)
        #expect(model.sessionFooterTitle?.detail.hasPrefix("3 selected") == true)

        model.addSelectedMedia()
        #expect(model.recipe.clips.map(\.assetID) == ["Falls", "Coast", "C", "A", "B", "Coast", "Lake", "Night", "Forest"])
        #expect(!model.isSelectingMedia)
        model.undo()
        #expect(model.recipe.clips.map(\.assetID) == ["Falls", "Coast", "Lake", "Night", "Forest"])

        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "A", kind: .photo))
        model.toggleMediaSelecting()
        #expect(model.mediaSelection == nil)
    }

    /// ✓ with picks not yet added adds them first, then closes Media.
    @Test func confirmAddsPendingSelection() {
        let model = sample()
        defer { model.close() }
        model.showToolPanel(.media)
        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "A", kind: .photo))
        model.toggleMediaPick(VideoMediaPick(assetID: "B", kind: .photo))
        model.commitSession()
        #expect(model.recipe.clips.count == 7)
        #expect(model.activeToolPanel == nil)
        #expect(model.mediaSelection == nil)
        // ✕ with picks adds nothing.
        model.showToolPanel(.media)
        model.toggleMediaSelecting()
        model.toggleMediaPick(VideoMediaPick(assetID: "C", kind: .photo))
        model.cancelSession()
        #expect(model.recipe.clips.count == 7)
    }
}
