import Foundation
import Testing
@testable import ShotDex

/// Cut to Beat on FS-12.12 §9's project: 3.0s photo · 6.2s video (source
/// 10s, trim 0–6.2) · 5.0s video (source 10s) · 3.0s photo · 6.8s video,
/// straight cuts, Morning Drive at 96 BPM on 0.0–18.4 — bars every 2.5s.
struct CutToBeatMathTests {
    static func project(clip2Source: Double = 10) -> VideoProjectRecipe {
        func photo(_ id: String) -> VideoClip {
            var clip = VideoClip(assetID: id, kind: .photo)
            clip.photoDuration = 3
            return clip
        }
        func video(_ id: String, _ seconds: Double, source: Double) -> VideoClip {
            var clip = VideoClip(assetID: id, kind: .video)
            clip.sourceDuration = source
            clip.trimEnd = seconds
            return clip
        }
        var recipe = VideoProjectRecipe(clips: [
            photo("Falls"), video("Coast", 6.2, source: clip2Source), video("Lake", 5, source: 10),
            photo("Night"), video("Forest", 6.8, source: 6.8),
        ])
        recipe.syncTransitionsWithClips()
        return recipe
    }

    /// AC-10: Every Bar — four cuts move, by −0.5 · +0.8 · +0.8 · +0.3s,
    /// the largest +0.8s; the project itself is not touched by a preview.
    @Test func previewSampleProject() {
        let recipe = Self.project()
        let preview = CutToBeatMath.preview(recipe, grid: BeatGridTests.grid, spacing: .everyBar)
        #expect(preview.cuts.map(\.target) == [2.5, 10.0, 15.0, 17.5])
        let shifts = preview.cuts.map { ($0.shift * 10).rounded() / 10 }
        #expect(shifts == [-0.5, 0.8, 0.8, 0.3])
        #expect(preview.movingCount == 4)
        #expect(abs(preview.largestShift - 0.8) < 1e-9)
        #expect(VideoStudioCopy.cutsMove(4, largest: 0.8, cannotMove: 0) == "4 cuts move · largest +0.8s")
        #expect(recipe.clips.map(\.effectiveDuration) == [3.0, 6.2, 5.0, 3.0, 6.8])
    }

    /// AC-11: applied — clip 1 2.5s, clip 2 7.5s (trim 0–7.5), clip 3 still
    /// 5.0s, clip 4 2.5s, clip 5 starting at 17.5s.
    @Test func applyStretchesPhotosTrimsVideos() {
        let applied = CutToBeatMath.preview(Self.project(), grid: BeatGridTests.grid, spacing: .everyBar).applied
        let durations = applied.clips.map { ($0.effectiveDuration * 1000).rounded() / 1000 }
        #expect(durations == [2.5, 7.5, 5.0, 2.5, 6.8])
        #expect(applied.clips[1].trimStart == 0 && abs((applied.clips[1].trimEnd ?? 0) - 7.5) < 1e-9)
        let placements = VideoTimelineMath.placements(durations: applied.clips.map(\.effectiveDuration), overlaps: [0, 0, 0, 0])
        #expect(abs(placements[4].start - 17.5) < 1e-9)
    }

    /// AC-12: clip 2's source is only 6.2s — the cut at 9.2 cannot reach
    /// 10.0 and clip 2 keeps its length; the others still move:
    /// "3 cuts move · largest +0.8s · 1 can't move".
    @Test func shortSourceCutStays() {
        let preview = CutToBeatMath.preview(Self.project(clip2Source: 6.2), grid: BeatGridTests.grid, spacing: .everyBar)
        #expect(preview.cuts.map(\.canMove) == [true, false, true, true])
        #expect(preview.movingCount == 3)
        #expect(preview.cannotMoveCount == 1)
        #expect(abs(preview.applied.clips[1].effectiveDuration - 6.2) < 1e-9)
        #expect(VideoStudioCopy.cutsMove(3, largest: preview.largestShift, cannotMove: 1) == "3 cuts move · largest +0.8s · 1 can't move")
    }

    /// 2 Bars and 4 Bars aim at every 2nd and 4th bar.
    @Test func widerSpacingsUseFewerBars() {
        #expect(CutToBeatMath.targets(BeatGridTests.grid, spacing: .twoBars) == [0, 5, 10, 15])
        #expect(CutToBeatMath.targets(BeatGridTests.grid, spacing: .fourBars) == [0, 10])
    }
}

/// Cut to Beat on the model (FS-12.12 §6), with the beats of a decoded
/// 96 BPM WAV for Morning Drive.
@MainActor
struct VideoCutToBeatModelTests {
    private func model(clip2Source: Double = 10) async throws -> (VideoStudioModel, URL) {
        let url = try MusicBeatAnalyzerTests.writeClickWAV(bpm: 96, seconds: 20)
        var bed = MusicTrack(source: .imported(url: url, displayName: "Morning Drive"))
        bed.sourceDuration = 20
        bed.trimEnd = 18.4
        bed.beatSnap.isOn = true
        let model = VideoStudioModelFixture.model(
            clips: CutToBeatMathTests.project(clip2Source: clip2Source).clips,
            configure: { $0.musicTracks = [bed] }
        )
        model.beats.findBeats(of: url)
        for _ in 0..<400 where model.beats.isFinding { try await Task.sleep(for: .milliseconds(10)) }
        model.selectMusic(model.recipe.musicTracks[0].id)
        model.toggleItemSection(.beats)
        return (model, url)
    }

    /// AC-11: Apply is one undo step for every length, and one Undo puts
    /// all five back.
    @Test func applyIsOneUndo() async throws {
        let (model, url) = try await model()
        defer { try? FileManager.default.removeItem(at: url) }
        model.beginCutToBeatPreview()
        let preview = try #require(model.cutToBeatPreview)
        #expect(preview.movingCount == 4)

        model.applyCutToBeat()
        let lengths = model.recipe.clips.map { ($0.effectiveDuration * 10).rounded() / 10 }
        #expect(lengths == [2.5, 7.5, 5.0, 2.5, 6.8])
        #expect(!model.isPreviewingCutToBeat)

        model.undo()
        #expect(model.recipe.clips.map(\.effectiveDuration) == [3.0, 6.2, 5.0, 3.0, 6.8])
    }

    /// AC-13: leaving the preview — the Ducking cell or any other command,
    /// ✕, another selection — changes neither the project nor the undo
    /// stack.
    @Test func leavingPreviewChangesNothing() async throws {
        let (model, url) = try await model()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = model.recipe
        let couldUndo = model.canUndo
        model.beginCutToBeatPreview()
        #expect(model.cutToBeatPreview != nil)

        model.toggleItemSection(.volume)
        #expect(!model.isPreviewingCutToBeat)
        #expect(model.recipe == before)
        #expect(model.canUndo == couldUndo)

        model.toggleItemSection(.beats)
        model.beginCutToBeatPreview()
        model.cancelSession()
        #expect(!model.isPreviewingCutToBeat)
        #expect(model.recipe == before)
    }
}
