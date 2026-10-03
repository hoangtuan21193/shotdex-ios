import Foundation
import ShotDexKit
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

/// Delete (FS-12.04 §5): one undo step, whoever asks, and the session ends
/// as ✓ ends it.
@MainActor
struct VideoDeleteTests {
    /// FS-12.04 AC-7: three clips, clip 2 selected, Delete — two clips end
    /// to end, nothing selected; one Undo puts clip 2 back where it was.
    @Test func deleteKeepsClipsContiguousAndUndoesOnce() {
        let model = VideoStudioModelFixture.model()
        let ids = model.recipe.clips.map(\.id)
        model.selectClip(ids[1])
        model.deleteClip(ids[1])

        #expect(model.recipe.clips.map(\.id) == [ids[0], ids[2]])
        let placements = model.clipPlacements
        #expect(placements[1].start == placements[0].end)
        #expect(model.selectedClipID == nil)
        #expect(model.session == nil)
        #expect(model.inspectorTarget == .none)

        model.undo()
        #expect(model.recipe.clips.map(\.id) == ids)
        #expect(!model.canUndo)
    }

    /// The transport's ⋯ menu deletes through the same command, so it is
    /// undoable too — it used to drop the clip with no way back.
    @Test func deleteFromTheTransportMenuIsUndoable() {
        let model = VideoStudioModelFixture.model()
        let ids = model.recipe.clips.map(\.id)
        model.selectClip(ids[2])
        // What the menu's Delete Clip calls.
        if let id = model.selectedClipID { model.deleteClip(id) }
        #expect(model.recipe.clips.count == 2)
        #expect(model.canUndo)
        model.undo()
        #expect(model.recipe.clips.map(\.id) == ids)
    }

    /// A caption and a music bed delete the same way.
    @Test func captionAndMusicDeletesAreOneStepEach() {
        let model = VideoStudioModelFixture.model { recipe in
            recipe.overlays = [TimedOverlay(overlay: PhotoOverlay.text())]
            recipe.musicTracks = [MusicTrack(source: .bundled(id: "calm"))]
        }
        model.selectOverlay(model.recipe.overlays[0].id)
        model.deleteSelectedOverlay()
        #expect(model.recipe.overlays.isEmpty)
        #expect(model.session == nil)
        model.selectMusic(model.recipe.musicTracks[0].id)
        model.removeMusicTrack(model.recipe.musicTracks[0].id)
        #expect(model.recipe.musicTracks.isEmpty)
        #expect(model.session == nil)
        model.undo()
        #expect(model.recipe.musicTracks.count == 1)
        model.undo()
        #expect(model.recipe.overlays.count == 1)
    }
}
