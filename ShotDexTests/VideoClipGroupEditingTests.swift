import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// The pure rules of a multi-select group (FS-12.11), on FS-12.11 §9's
/// sample project: 3.0s photo · 6.2s video · 5.0s video · 3.0s photo ·
/// 6.8s video, every boundary a straight cut.
struct VideoClipGroupEditingTests {
    private let recipe = VideoStudioModelFixture.mediaSampleRecipe()
    private var ids: [UUID] { recipe.clips.map(\.id) }

    /// AC-2's lines: clips 2, 3, 4 are 14.2s of two videos and a photo;
    /// clips 2 and 3 are all video, so the count of kinds is left off.
    @Test func summaryCountsKinds() {
        let three = VideoClipGroupEditing.summary(of: [ids[1], ids[2], ids[3]], in: recipe)
        #expect(three == .init(count: 3, seconds: 14.2, videos: 2, photos: 1))
        #expect(VideoStudioCopy.groupDetail(three) == "14.2s · 2 videos + 1 photo")
        #expect(VideoStudioCopy.groupDetail(three, includesKinds: false) == "14.2s")
        #expect(VideoStudioCopy.selectedCount(3) == "3 selected")
        #expect(VideoStudioCopy.clipCount(3) == "3 Clips")

        let videos = VideoClipGroupEditing.summary(of: [ids[1], ids[2]], in: recipe)
        #expect(VideoStudioCopy.groupDetail(videos) == "11.2s")
        let photosAndOneVideo = VideoClipGroupEditing.summary(of: [ids[0], ids[1], ids[3]], in: recipe)
        #expect(VideoStudioCopy.groupDetail(photosAndOneVideo) == "12.2s · 1 video + 2 photos")
    }

    /// The group is held in timeline order whatever order it was tapped in,
    /// and Shift-click's run includes both ends.
    @Test func orderAndRangeFollowTheTimeline() {
        #expect(VideoClipGroupEditing.ordered([ids[3], ids[1], UUID()], in: recipe) == [ids[1], ids[3]])
        #expect(VideoClipGroupEditing.range(from: ids[3], to: ids[1], in: recipe) == [ids[1], ids[2], ids[3]])
    }

    /// AC-4: a group of clips 1 and 4, both photos, has five commands —
    /// Look · Motion · Move · Duplicate · Delete; Speed and Volume, which
    /// only touch video, are hidden rather than dimmed.
    @Test func photoOnlyGroupHasFiveCommands() {
        let photos = VideoClipGroupEditing.summary(of: [ids[0], ids[3]], in: recipe)
        #expect(!photos.hasVideo)
        #expect(VideoItemCommand.groupCommands(hasVideo: photos.hasVideo) == [.look, .motion, .move, .duplicate, .delete])
        let mixed = VideoClipGroupEditing.summary(of: [ids[0], ids[1]], in: recipe)
        #expect(VideoItemCommand.groupCommands(hasVideo: mixed.hasVideo) == [.speed, .volume, .look, .motion, .move, .duplicate, .delete])
    }

    /// AC-3: 2× on clips 2, 3, 4 — the videos halve to 3.1s and 2.5s, the
    /// photo keeps its 3.0s, the project runs 18.4s; the line under Speed
    /// says exactly that, and differing speeds read as "Mixed".
    @Test func speedTouchesOnlyVideos() {
        var edited = recipe
        let group = [ids[1], ids[2], ids[3]]
        #expect(VideoClipGroupEditing.commonSpeed(of: group, in: edited) == 1)
        VideoClipGroupEditing.setSpeed(2, for: group, in: &edited)
        #expect(edited.clips.map(\.effectiveDuration) == [3.0, 3.1, 2.5, 3.0, 6.8])
        #expect(abs(edited.clips.map(\.effectiveDuration).reduce(0, +) - 18.4) < 1e-9)
        #expect(VideoClipGroupEditing.commonSpeed(of: group, in: edited) == 2)
        #expect(VideoClipGroupEditing.commonSpeed(of: [ids[1], ids[4]], in: edited) == nil)
        #expect(VideoClipGroupEditing.commonSpeed(of: [ids[0], ids[3]], in: edited) == nil)
        #expect(VideoStudioCopy.speedNote(
            videos: 2, stills: VideoClipGroupEditing.stillsSpeedLeaves(group, in: edited)
        ) == "Applies to the 2 videos · the photo keeps its 3.0s")
        #expect(VideoStudioCopy.speedNote(videos: 1, stills: [edited.clips[0]]) == "Applies to the video · the photo keeps its 3.0s")
        #expect(VideoStudioCopy.speedNote(videos: 2, stills: []) == nil)
    }

    /// AC-5: clip 2 muted, clip 3 not — the speaker reads on; muting is for
    /// the whole group, and only videos carry sound to mute.
    @Test func speakerMutesWholeMixedGroup() {
        var edited = recipe
        edited.clips[1].isMuted = true
        let group = [ids[1], ids[2]]
        #expect(!VideoClipGroupEditing.isMuted(group, in: edited))
        VideoClipGroupEditing.setMuted(true, for: group + [ids[3]], in: &edited)
        #expect(edited.clips.map(\.isMuted) == [false, true, true, false, false])
        #expect(VideoClipGroupEditing.isMuted(group, in: edited))
    }

    /// AC-19: Fade in 2.0s on clip 2 (6.2s video) and clip 4 (3.0s photo)
    /// — clip 2 fades 2.0s, clip 4 is held to half its length, 1.5s.
    @Test func groupFadeClampsPerClip() {
        var edited = recipe
        let group = [ids[1], ids[3]]
        VideoClipGroupEditing.setFade(2.0, atStart: true, for: group, in: &edited)
        #expect(edited.clips[1].fadeIn == 2.0)
        #expect(edited.clips[3].fadeIn == 1.5)
        #expect(edited.clips[1].fadeOut == 0)
        #expect(VideoClipGroupEditing.commonFade(group, atStart: true, in: edited) == nil)
        #expect(VideoClipGroupEditing.maximumFade(group, in: edited) == 3.1)
    }

    /// AC-6: clips 2 and 3 duplicated — 7 clips, the copies at positions 4
    /// and 5 with the same speed, look and motion and their own ids; the
    /// boundary 3 → copy is a straight cut; the project runs 35.2s.
    @Test func duplicateInsertsAfterLastKeepsOrder() {
        var edited = recipe
        edited.clips[1].speed = 2
        edited.clips[2].effect = .zoomIn
        edited.clips[2].look = VideoLook(.preset(.vivid))
        edited.transitions[1] = .defaultCrossfade
        let before = edited
        let pairs = VideoClipGroupEditing.duplicate([ids[2], ids[1]], in: &edited)

        #expect(edited.clips.count == 7)
        #expect(pairs.map(\.original) == [ids[1], ids[2]])
        #expect(edited.clips.map(\.id) == [ids[0], ids[1], ids[2], pairs[0].copy, pairs[1].copy, ids[3], ids[4]])
        #expect(Set(pairs.map(\.copy)).isDisjoint(with: Set(ids)))
        #expect(edited.clips[3].speed == 2 && edited.clips[3].assetID == before.clips[1].assetID)
        #expect(edited.clips[4].effect == .zoomIn && edited.clips[4].look == before.clips[2].look)
        // 2 → 3 kept its crossfade; 3 → copy, copy → copy, copy → 4 are new.
        #expect(edited.transitions.map(\.kind) == [.none, .crossfade, .none, .none, .none, .none])
        let total = VideoTimelineMath.placements(
            durations: edited.clips.map(\.effectiveDuration),
            overlaps: VideoTimelineMath.effectiveOverlaps(requested: edited.transitions.map(\.requestedOverlap), durations: edited.clips.map(\.effectiveDuration))
        ).last?.end ?? 0
        // 35.2s at 1×; clip 2 and its copy at 2× give 3.1s back each, the crossfade 0.5s.
        #expect(abs(total - (35.2 - 3.1 - 3.1 - 0.5)) < 1e-9)
    }

    /// The pair rule on its own: boundaries between clips that stay
    /// neighbours keep their transition, new ones are cuts.
    @Test func transitionsFollowTheirTwoClips() {
        var old = recipe
        old.transitions[0] = .defaultCrossfade
        old.transitions[2] = VideoBoundaryTransition(kind: .wipe, duration: 1)
        let reordered = [old.clips[0], old.clips[1], old.clips[3], old.clips[2], old.clips[4]]
        let remapped = VideoClipGroupEditing.remapTransitions(from: old, to: reordered)
        #expect(remapped.map(\.kind) == [.crossfade, .none, .none, .none])
        let reversed = VideoClipGroupEditing.remapTransitions(from: old, to: [old.clips[2], old.clips[3]])
        #expect(reversed.map(\.kind) == [.wipe])
    }

    /// AC-7: clips 2, 3, 4 deleted with a Crossfade on 1 → 2 — clips 1 and 5
    /// close up, 1 → 5 is a straight cut (the crossfade was for 1 → 2),
    /// 9.8s. Deleting every clip is refused and changes nothing.
    @Test func deleteMiddleThreeLeavesNoneBoundary() {
        var edited = recipe
        edited.transitions[0] = .defaultCrossfade
        #expect(VideoClipGroupEditing.delete([ids[1], ids[2], ids[3]], in: &edited))
        #expect(edited.clips.map(\.id) == [ids[0], ids[4]])
        #expect(edited.transitions.map(\.kind) == [.none])
        #expect(abs(edited.clips.map(\.effectiveDuration).reduce(0, +) - 9.8) < 1e-9)

        var all = recipe
        #expect(!VideoClipGroupEditing.delete(ids, in: &all))
        #expect(all == recipe)
    }
}
