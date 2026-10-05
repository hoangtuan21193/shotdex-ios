import CoreGraphics
import ShotDexKit
import Testing
@testable import ShotDex

/// A selected item's command row (FS-12.04b §3).
struct VideoItemCommandsTests {
    /// FS-12.04b AC-1: a video clip's row in the spec's order, Delete last
    /// and red. Look (FS-12.06c) is hidden until its plan lands, like Beats
    /// and Ducking — the rest keep their order.
    @Test func videoClipRowIsTheSpecOrder() {
        let row = VideoItemCommand.commands(for: .videoClip)
        let spec: [VideoItemCommand] = [.split, .trim, .speed, .volume, .replace, .freeze, .duplicate, .look, .delete]
        #expect(row == spec.filter { !VideoItemCommand.notYetBuilt.contains($0) })
        #expect(row.last == .delete)
        #expect(row.last?.isDestructive == true)
        #expect(row.filter(\.isDestructive) == [.delete])
        // Single-video mode: Rotate right before Delete (FS-12.04b §3, Q-9).
        let single = VideoItemCommand.commands(for: .videoClip, singleVideo: true)
        #expect(Array(single.suffix(2)) == [.rotate, .delete])
        // No Mute cell: mute is the speaker at the head of the Volume row.
        #expect(!row.map(\.rawValue).contains("mute"))
    }

    /// Every kind's row is the spec's, Delete last, no command twice.
    @Test func everyKindsRowEndsWithDelete() {
        for kind in VideoItemKind.allCases {
            let row = VideoItemCommand.commands(for: kind)
            #expect(row.last == .delete, "\(kind)")
            #expect(Set(row).count == row.count, "\(kind)")
        }
        #expect(VideoItemCommand.commands(for: .text) == [.edit, .font, .color, .style, .align, .animate, .duplicate, .delete])
        #expect(VideoItemCommand.commands(for: .sticker) == [.animate, .duplicate, .delete])
        // Beats is built (FS-12.12); Ducking waits for FS-12.13.
        #expect(VideoItemCommand.commands(for: .music) == [.beats, .replace, .addTrack, .duplicate, .delete])
    }

    @Test func sectionsAndActions() {
        for command in [VideoItemCommand.trim, .speed, .volume, .edit, .animate] { #expect(command.isSection) }
        for command in [VideoItemCommand.split, .replace, .freeze, .duplicate, .addTrack, .delete] { #expect(!command.isSection) }
    }
}

extension VideoItemCommandsTests {
    /// FS-12.04b AC-2: a photo clip — Split · Trim · Replace · Duplicate ·
    /// Look · Delete; no Speed, Volume or Freeze cell.
    @Test func photoRowHasNoSpeedVolumeFreeze() {
        let row = VideoItemCommand.commands(for: .photoClip)
        let spec: [VideoItemCommand] = [.split, .trim, .replace, .duplicate, .look, .delete]
        #expect(row == spec.filter { !VideoItemCommand.notYetBuilt.contains($0) })
        for absent in [VideoItemCommand.speed, .volume, .freeze] {
            #expect(!row.contains(absent))
        }
        #expect(VideoItemCommand.commands(for: .freezeClip) == [.split, .trim, .duplicate, .look, .delete])
    }
}

extension VideoItemCommandsTests {
    /// FS-12.04b AC-3: every layout reads the same list for every kind of
    /// item — compared element by element against the phone's — and lays
    /// it out as one scrolling row.
    @Test func everyLayoutGetsTheSameCommands() {
        for kind in VideoItemKind.allCases {
            let phone = VideoItemCommand.commands(for: kind, in: .phone)
            for windowClass in VideoStudioWindowClass.allCases {
                #expect(VideoItemCommand.commands(for: kind, in: windowClass) == phone, "\(kind) on \(windowClass)")
                #expect(VideoItemCommand.rowShape(in: windowClass) == .scrollingRow)
            }
        }
    }
}

/// Section commands light and unlight (FS-12.04b §4).
@MainActor
struct VideoItemSectionTests {
    /// FS-12.04b AC-4: Trim lights its cell and puts its block on top.
    @Test func trimTogglesItsBlock() {
        let model = VideoStudioModelFixture.model()
        model.selectClip(model.recipe.clips[1].id)
        model.toggleItemSection(.trim)
        #expect(model.activeItemCommand == .trim)
        #expect(model.isItemCommandOn(.trim))
        #expect(!model.isItemCommandOn(.split))
        // A new selection starts with nothing lit.
        model.selectClip(model.recipe.clips[2].id)
        #expect(model.activeItemCommand == nil)
    }

    /// FS-12.04b AC-5: Trim again turns it off; the content starts with
    /// Speed again.
    @Test func tappingTrimAgainReturnsToSpeed() {
        let model = VideoStudioModelFixture.model()
        model.selectClip(model.recipe.clips[1].id)
        model.toggleItemSection(.trim)
        model.toggleItemSection(.trim)
        #expect(model.activeItemCommand == nil)
        #expect(VideoClipPanelSections.sections(for: .video, leading: model.activeItemCommand).first == .speed)
        model.toggleItemSection(.volume)
        #expect(VideoClipPanelSections.sections(for: .video, leading: model.activeItemCommand).first == .volume)
    }
}

/// The speaker at the head of a Volume row (FS-12.04b §5).
@MainActor
struct VideoMuteSpeakerTests {
    /// FS-12.04b AC-6: clip 2 at Volume 80 — the speaker once: silent, the
    /// level still 80; again: 80 audible; two undo steps.
    @Test func muteKeepsTheLevelAndUndoesStepwise() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.setClipVolume(0.8, for: clip2)
        model.selectClip(clip2)

        model.toggleClipMuted(clip2)
        #expect(model.recipe.clips[1].isMuted)
        #expect(model.recipe.clips[1].volume == 0.8)
        model.toggleClipMuted(clip2)
        #expect(!model.recipe.clips[1].isMuted)
        #expect(model.recipe.clips[1].volume == 0.8)
        #expect(model.history.undoEntries.count == 2)
        model.undo()
        #expect(model.recipe.clips[1].isMuted)
        model.undo()
        #expect(!model.recipe.clips[1].isMuted)

        // A music bed's speaker keeps its level the same way.
        model.addMusicTrack(source: .bundled(id: "calm"))
        let bed = model.recipe.musicTracks[0].id
        model.setMusicVolume(0.6, for: bed)
        model.toggleMusicMuted(bed)
        #expect(model.recipe.musicTracks[0].isMuted)
        #expect(model.recipe.musicTracks[0].volume == 0.6)
        // No Mute cell in the row: the speaker is the one way.
        #expect(!VideoItemCommand.commands(for: .music).map(\.rawValue).contains("mute"))
    }
}

/// Split and Duplicate open sessions of their own (FS-12.04b §4).
@MainActor
struct VideoSplitDuplicateTests {
    /// FS-12.04b AC-7: a 10 s clip selected, playhead at 4 s, Split, then ✕
    /// — still two clips, 0–4 and 4–10, nothing selected. ✕ belongs to the
    /// right half's session; the cut belonged to the clip's, which Split
    /// ended as ✓.
    @Test func splitThenCancelKeepsTheCut() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.videoClips(1))
        model.selectClip(model.recipe.clips[0].id)
        model.seek(to: 4)
        model.splitClipUnderPlayhead()
        #expect(model.recipe.clips.count == 2)
        #expect(model.selectedClipID == model.recipe.clips[1].id)

        model.cancelSession()
        #expect(model.recipe.clips.count == 2)
        #expect(model.recipe.clips[0].trimStart == 0)
        #expect(model.recipe.clips[0].trimEnd == 4)
        #expect(model.recipe.clips[1].trimStart == 4)
        #expect(model.recipe.clips[1].trimEnd == 10)
        #expect(model.selectedClipID == nil)
    }
}

extension VideoSplitDuplicateTests {
    /// FS-12.04b AC-8: GOLDEN HOUR selected, Duplicate, ✕ — exactly one
    /// GOLDEN HOUR block, nothing selected, no step left of the copy.
    @Test func duplicateThenCancelLeavesOneBlock() {
        var overlay = PhotoOverlay.text()
        overlay.text = "GOLDEN HOUR"
        let model = VideoStudioModelFixture.model { $0.overlays = [TimedOverlay(overlay: overlay, start: 1, duration: 4)] }
        model.selectOverlay(overlay.id)
        model.duplicateSelectedOverlay()
        #expect(model.recipe.overlays.count == 2)
        #expect(model.selectedOverlayID != overlay.id)

        model.cancelSession()
        #expect(model.recipe.overlays.map(\.id) == [overlay.id])
        #expect(model.selectedOverlayID == nil)
        #expect(!model.canUndo)
    }

    /// A duplicated clip lands right after the original, shares its source,
    /// and is selected; a duplicated bed starts where the original ends.
    @Test func duplicateClipInsertsAfterAndSharesTheSource() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(3))
        let original = model.recipe.clips[1]
        model.sources[original.id] = .photo(assetID: original.assetID, pixelSize: CGSize(width: 10, height: 10))
        model.selectClip(original.id)
        model.duplicateSelectedClip()

        #expect(model.recipe.clips.count == 4)
        let copy = model.recipe.clips[2]
        #expect(copy.assetID == original.assetID)
        #expect(copy.id != original.id)
        #expect(copy.photoDuration == original.photoDuration)
        #expect(model.selectedClipID == copy.id)
        #expect(model.sources[copy.id] != nil)
        model.cancelSession()
        #expect(model.recipe.clips.count == 3)

        var bed = MusicTrack(source: .bundled(id: "calm"))
        bed.sourceDuration = 5
        bed.trimEnd = 5
        let withMusic = VideoStudioModelFixture.model { $0.musicTracks = [bed] }
        withMusic.selectMusic(bed.id)
        withMusic.duplicateSelectedMusic()
        #expect(withMusic.recipe.musicTracks.count == 2)
        #expect(withMusic.recipe.musicTracks[1].start == 5)
    }
}
