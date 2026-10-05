import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// Multi-select in the Video Studio (FS-12.11): entering, the group's
/// commands, undo and ✕ — on the model, over FS-12.11 §9's sample project:
/// 3.0s photo · 6.2s video · 5.0s video · 3.0s photo · 6.8s video.
@MainActor
struct VideoStudioMultiSelectTests {
    private func sampleModel() -> VideoStudioModel {
        VideoStudioModelFixture.model(clips: VideoStudioModelFixture.mediaSampleRecipe().clips)
    }

    /// AC-1: clip 2 held half a second and let go — a group of one: the
    /// footer says "1 Clip" over its length, the row is the group's seven
    /// commands, Speed to Delete, and nothing was changed.
    @Test func holdReleaseEntersWithOneClip() {
        let model = sampleModel()
        let clip2 = model.recipe.clips[1].id
        let before = model.recipe

        model.enterClipSelection(clip2)

        #expect(model.isSelectingClips)
        #expect(model.selectedClipIDs == [clip2])
        #expect(model.inspectorTarget == .clips)
        #expect(model.selectedClipID == nil)
        #expect(model.session?.target == .clipGroup)
        #expect(model.selectionTitle == VideoItemTitle.Lines(name: "1 Clip", detail: "6.2s"))
        #expect(VideoStudioCopy.selectedCount(1) == "1 selected")
        #expect(model.selectedItemCommands == [.speed, .volume, .look, .motion, .move, .duplicate, .delete])
        #expect(model.recipe == before)
        #expect(!model.canUndo)
    }

    /// Entering a group keeps whatever was open, as ✓ does: clip 1's change
    /// stays and stays undoable.
    @Test func enteringKeepsTheOpenSession() {
        let model = sampleModel()
        let clip1 = model.recipe.clips[0].id
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip1)
        model.pushUndo()
        model.setPhotoDuration(4, for: clip1)

        model.enterClipSelection(clip2)

        #expect(model.recipe.clips[0].photoDuration == 4)
        #expect(model.canUndo)
        #expect(model.selectedClipID == nil)
        #expect(model.selectedClipIDs == [clip2])
    }

    /// The phone's group panel lifts the stack only as far as keeps the
    /// video lane 8 clear of it: nothing for the 16:9 board (timeline at
    /// 326, lane bottom 147 under it, panel top 518), the difference for a
    /// square frame that pushed the timeline down to 490.
    @Test func phoneGroupPanelLiftsOnlyWhatTheLaneNeeds() {
        #expect(VideoStudioMetrics.groupPanelLift(timelineTop: 326, videoLaneBottom: 147, panelTop: 518) == 0)
        #expect(VideoStudioMetrics.groupPanelLift(timelineTop: 490, videoLaneBottom: 147, panelTop: 518) == 127)
    }

    /// AC-2: clips 3 and 4 tapped into clip 2's group — "3 selected ·
    /// 14.2s"; clip 3 tapped again leaves two. Tapping the last ones out
    /// ends the group as ✓ does: nothing selected, the tools back.
    @Test func toggleDownToZeroExitsLikeDone() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[2])
        model.toggleClip(ids[3])
        #expect(model.selectedClipIDs == [ids[1], ids[2], ids[3]])
        #expect(model.groupSummary.seconds == 14.2)
        #expect(model.selectionTitle?.detail == "14.2s · 2 videos + 1 photo")

        model.toggleClip(ids[2])
        #expect(model.selectedClipIDs == [ids[1], ids[3]])

        model.toggleClip(ids[1])
        model.toggleClip(ids[3])
        #expect(!model.isSelectingClips)
        #expect(model.session == nil)
        #expect(model.inspectorTarget == .none)
    }

    /// A caption or a music bed tapped while a group is open: the group
    /// ends as ✓ ends it, then that item is selected (FS-12.11 §4).
    @Test func tappingAnotherItemKeepsAndMovesOn() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.overlays = VideoStudioModelFixture.mediaSampleRecipe().overlays }
        )
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleOverlay(model.recipe.overlays[0].id)
        #expect(!model.isSelectingClips)
        #expect(model.inspectorTarget == .text)
    }

    /// The iPad's pointer: Shift-click adds the run of clips up to the one
    /// clicked, ⌘-click toggles one, and ⌘-click with no group starts one.
    @Test func pointerClicksExtendAndToggle() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.commandClickClip(ids[1])
        #expect(model.selectedClipIDs == [ids[1]])
        model.shiftClickClip(ids[3])
        #expect(model.selectedClipIDs == [ids[1], ids[2], ids[3]])
        model.commandClickClip(ids[2])
        #expect(model.selectedClipIDs == [ids[1], ids[3]])
        model.commandClickClip(ids[0])
        #expect(model.selectedClipIDs == [ids[0], ids[1], ids[3]])
    }

    /// AC-4 on the model: clips 1 and 4 selected, the row is the five
    /// commands a photo can take.
    @Test func photoOnlyGroupRowHasNoSpeedOrVolume() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[0])
        model.toggleClip(ids[3])
        #expect(model.selectedItemCommands == [.look, .motion, .move, .duplicate, .delete])
    }

    /// AC-3: the 2× chip is one step — one Undo puts both videos back to
    /// 1×, and the photo never moved.
    @Test func oneUndoRestoresBothSpeeds() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[2])
        model.toggleClip(ids[3])

        model.chooseGroupSpeed(2)
        #expect(model.recipe.clips.map(\.speed) == [1, 2, 2, 1, 1])
        #expect(model.groupSpeed == 2)

        model.undo()
        #expect(model.recipe.clips.map(\.speed) == [1, 1, 1, 1, 1])
        #expect(!model.canUndo)
        #expect(model.isSelectingClips)
    }

    /// A Speed slider drag across the group is one step too.
    @Test func groupSpeedDragIsOneStep() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[4])
        model.beginUndoGroup()
        model.setGroupSpeed(1.5)
        model.setGroupSpeed(3)
        model.endUndoGroup()
        #expect(model.recipe.clips[1].speed == 3)
        #expect(model.recipe.clips[4].speed == 3)
        model.undo()
        #expect(model.recipe.clips[1].speed == 1)
        #expect(!model.canUndo)
    }
}
