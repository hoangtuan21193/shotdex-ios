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

    /// AC-5: one tap on the speaker mutes clip 2 (already muted) and clip 3;
    /// one Undo puts back exactly the mix there was.
    @Test func oneUndoRestoresMixedMute() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.clips[1].isMuted = true }
        )
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[2])
        #expect(!model.isGroupMuted)

        model.toggleGroupMuted()
        #expect(model.recipe.clips[1].isMuted && model.recipe.clips[2].isMuted)
        #expect(model.isGroupMuted)

        model.undo()
        #expect(model.recipe.clips[1].isMuted)
        #expect(!model.recipe.clips[2].isMuted)
        #expect(!model.canUndo)
    }

    /// AC-19: the Fade in drag across clips 2 and 4 is one step; one Undo
    /// puts both back to no fade.
    @Test func groupFadeIsOneUndo() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[3])
        model.beginUndoGroup()
        model.setGroupFade(1.0, at: .start)
        model.setGroupFade(2.0, at: .start)
        model.endUndoGroup()
        #expect(model.recipe.clips[1].fadeIn == 2.0)
        #expect(model.recipe.clips[3].fadeIn == 1.5)
        model.undo()
        #expect(model.recipe.clips[1].fadeIn == 0)
        #expect(model.recipe.clips[3].fadeIn == 0)
        #expect(!model.canUndo)
    }

    /// AC-20: clips 1 and 4 (both photos), Motion None — Zoom In on both in
    /// one tap; one Undo puts both back to None.
    @Test func groupMotionAppliesToAll() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[0])
        model.toggleClip(ids[3])
        #expect(model.groupEffect == VideoClipEffect.none)

        model.setGroupEffect(.zoomIn)
        #expect(model.recipe.clips.map(\.effect) == [.zoomIn, .none, .none, .zoomIn, .none])
        #expect(model.groupEffect == .zoomIn)

        model.undo()
        #expect(model.recipe.clips.map(\.effect) == Array(repeating: VideoClipEffect.none, count: 5))
        #expect(!model.canUndo)
    }

    /// The group's Look (06c's Selected): the Look command opens the clip
    /// block aimed at every clip of the group; one tile, one step, every
    /// clip gets the look; the row then names it, and differing looks read
    /// "Mixed".
    @Test func groupLookWritesEverySelectedClip() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[3])
        #expect(model.groupLookName == VideoStudioCopy.wholeVideo)

        model.toggleItemSection(.look)
        #expect(model.lookTarget == .selected)
        #expect(model.canTargetSelectedClips)
        #expect(model.lookSubtitle == "2 Clips")

        model.chooseLook(.preset(.vivid))
        #expect(model.recipe.clips[1].look?.source == .preset(.vivid))
        #expect(model.recipe.clips[3].look?.source == .preset(.vivid))
        #expect(model.recipe.clips[0].look == nil)
        #expect(model.groupLookName != VideoStudioCopy.mixed)

        model.toggleClip(ids[0])
        #expect(model.groupLookName == VideoStudioCopy.mixed)

        model.undo()
        #expect(model.recipe.clips[1].look == nil && model.recipe.clips[3].look == nil)
    }

    /// AC-6 on the model: Duplicate on clips 2, 3 is one step, the copies
    /// become the group, and one Undo is back to five clips.
    @Test func duplicateIsOneUndo() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[2])

        model.duplicateGroup()
        #expect(model.recipe.clips.count == 7)
        #expect(model.selectedClipIDs == [model.recipe.clips[3].id, model.recipe.clips[4].id])
        #expect(abs(model.recipe.clips.map(\.effectiveDuration).reduce(0, +) - 35.2) < 1e-9)
        #expect(model.recipe.transitions.count == 6)

        model.undo()
        #expect(model.recipe.clips.map(\.id) == ids)
        #expect(!model.canUndo)
    }

    /// AC-7 on the model: Delete leaves the group and is one step; one Undo
    /// brings back the five clips **and** the crossfade on 1 → 2.
    @Test func oneUndoRestoresClipsAndCrossfade() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.transitions[0] = .defaultCrossfade }
        )
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[1])
        model.toggleClip(ids[2])
        model.toggleClip(ids[3])

        model.deleteGroup()
        #expect(model.recipe.clips.map(\.id) == [ids[0], ids[4]])
        #expect(model.recipe.transitions.map(\.kind) == [.none])
        #expect(!model.isSelectingClips)
        #expect(model.session == nil)

        model.undo()
        #expect(model.recipe.clips.map(\.id) == ids)
        #expect(model.recipe.transitions[0].kind == .crossfade)
    }

    /// Q-a for one clip: deleting clip 2 with a crossfade on 2 → 3 no
    /// longer slides that crossfade onto 1 → 3.
    @Test func deletingOneClipLeavesACut() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.transitions[1] = .defaultCrossfade }
        )
        let ids = model.recipe.clips.map(\.id)
        model.deleteClip(ids[1])
        #expect(model.recipe.clips.map(\.id) == [ids[0], ids[2], ids[3], ids[4]])
        #expect(model.recipe.transitions.map(\.kind) == [.none, .none, .none])
    }

    /// AC-8: every clip in the group — Delete is drawn dimmed (it applies,
    /// it is only blocked) and does nothing when tapped.
    @Test func deletingEveryClipIsRefused() {
        let model = sampleModel()
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[0])
        for id in ids.dropFirst() { model.toggleClip(id) }
        #expect(model.selectedItemCommands.last == .delete)
        #expect(!model.isItemCommandEnabled(.delete))
        #expect(model.isItemCommandEnabled(.duplicate))

        model.deleteGroup()
        #expect(model.recipe.clips.map(\.id) == ids)
        #expect(model.isSelectingClips)
        #expect(!model.canUndo)

        model.toggleClip(ids[4])
        #expect(model.isItemCommandEnabled(.delete))
    }

    /// AC-9 on the model: the group move is one step and keeps the group;
    /// one Undo puts back the order **and** the crossfade on 1 → 2.
    @Test func oneUndoRestoresOrderAndCrossfade() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.transitions[0] = .defaultCrossfade; $0.transitions[2] = .defaultCrossfade }
        )
        let ids = model.recipe.clips.map(\.id)
        model.enterClipSelection(ids[2])
        model.toggleClip(ids[3])

        #expect(model.moveClips(model.selectedClipIDs, toBoundary: 1))
        #expect(model.recipe.clips.map(\.id) == [ids[0], ids[2], ids[3], ids[1], ids[4]])
        #expect(model.selectedClipIDs == [ids[2], ids[3]])
        #expect(model.recipe.transitions.map(\.kind) == [.none, .crossfade, .none, .none])

        model.undo()
        #expect(model.recipe.clips.map(\.id) == ids)
        #expect(model.recipe.transitions.map(\.kind) == [.crossfade, .none, .crossfade, .none])
        #expect(!model.canUndo)
    }

    /// AC-11 on the model: a drop at the group's own place adds no undo
    /// step and leaves order and transitions as they were.
    @Test func cancelledDragAddsNoUndo() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.transitions[2] = .defaultCrossfade }
        )
        let ids = model.recipe.clips.map(\.id)
        let before = model.recipe
        model.enterClipSelection(ids[2])
        model.toggleClip(ids[3])
        #expect(!model.moveClips(model.selectedClipIDs, toBoundary: 2))
        #expect(!model.moveClips(model.selectedClipIDs, toBoundary: 4))
        #expect(model.recipe == before)
        #expect(!model.canUndo)
    }
}
