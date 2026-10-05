import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-12.06c §7: the Look panel is a session — ✕ puts the project back as
/// it was when the panel opened and leaves no undo step; ✓ keeps each step.
/// The session is the studio's own (`VideoEditSession`, FS-12.04 §5).
@MainActor
struct VideoLookSessionTests {
    static let moody = VideoLook.Source.myLook(
        sourceID: UUID(uuidString: "00000000-0000-0000-0000-00000000C0A5")!,
        name: "Moody Coast", isImported: false, recipe: VideoLookSamples.moodyCoast
    )

    /// Velvia, Moody Coast, Amount 70 in one drag.
    private func threeSteps(on model: VideoStudioModel) {
        model.toggleToolPanel(.look)
        model.chooseLook(VideoLookSamples.velvia.source)
        model.chooseLook(Self.moody)
        model.beginUndoGroup()
        for value in [0.9, 0.8, 0.7] { model.setLookAmount(value) }
        model.endUndoGroup()
    }

    /// AC-9: ✕ — no look, and as many undo steps as before the panel opened.
    @Test func cancelRestoresAndLeavesNoUndo() {
        let model = VideoStudioModelFixture.model()
        model.setVideoVolume(0.5)
        let before = model.history.undoEntries.count
        let start = model.recipe
        threeSteps(on: model)
        #expect(model.recipe.look?.amount == 0.7)
        #expect(model.history.undoEntries.count == before + 3)
        model.cancelSession()
        #expect(model.recipe.look == nil)
        #expect(model.recipe == start)
        #expect(model.history.undoEntries.count == before)
        #expect(!model.canRedo)
        #expect(model.activeToolPanel == nil)
    }

    /// AC-10: ✓, then Undo three times, one at a time: Moody Coast at 100,
    /// then Velvia, then no look.
    @Test func commitKeepsEachStep() {
        let model = VideoStudioModelFixture.model()
        threeSteps(on: model)
        model.commitSession()
        #expect(model.activeToolPanel == nil)
        #expect(model.recipe.look?.source == Self.moody)
        model.undo()
        #expect(model.recipe.look?.source == Self.moody)
        #expect(model.recipe.look?.amount == 1)
        model.undo()
        #expect(model.recipe.look == VideoLookSamples.velvia)
        model.undo()
        #expect(model.recipe.look == nil)
    }
}
