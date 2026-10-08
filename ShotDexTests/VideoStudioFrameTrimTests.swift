import Foundation
import Testing
@testable import ShotDex

/// The frame trim through the model (FS-12.17 §3): ✓ is one undo step, ✕
/// is none, Back keeps it. The sample project of §12.
@MainActor
struct VideoStudioFrameTrimTests {
    private func trimmedFourFrames() -> (VideoStudioModel, UUID) {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.beginFrameTrim(clip2, edge: .trailing)
        for _ in 0..<4 { model.stepFrameTrim(-1) }
        return (model, clip2)
    }

    /// FS-12.17 AC-3: ✓ after −4 frames — Clip 2 is 6.067 s (±1 ms), Clip 3
    /// starts at 9.067 s, exactly one undo step, and one Undo gives 6.2 back.
    @Test func commitAddsOneUndo() {
        let (model, clip2) = trimmedFourFrames()
        #expect(!model.canUndo)
        model.commitFrameTrim()
        #expect(!model.isFrameTrimming)
        let clip = model.recipe.clips.first { $0.id == clip2 }
        #expect(abs((clip?.effectiveDuration ?? 0) - 6.0667) < 0.001)
        #expect(abs(model.clipPlacements[2].start - 9.0667) < 0.001)
        #expect(model.canUndo)
        // The clip stays selected: the trim was a step inside its session.
        #expect(model.selectedClipID == clip2)
        model.undo()
        #expect(abs((model.recipe.clips[1].effectiveDuration) - 6.2) < 1e-9)
        #expect(!model.canUndo)
    }

    /// §3: Back while trimming is ✓, then leaving — the trim is kept.
    @Test func backCommitsFirst() async {
        let (model, clip2) = trimmedFourFrames()
        _ = await model.back()
        #expect(!model.isFrameTrimming)
        let clip = model.recipe.clips.first { $0.id == clip2 }
        #expect(abs((clip?.effectiveDuration ?? 0) - 6.0667) < 0.001)
        #expect(model.canUndo)
    }

    /// Any way out of the clip that keeps (an empty stretch of timeline,
    /// another clip) keeps the trim too; nothing moved writes nothing.
    @Test func deselectingKeepsTheTrimAndAnUnmovedTrimWritesNothing() {
        let (model, clip2) = trimmedFourFrames()
        model.clearSelection()
        #expect(abs((model.recipe.clips.first { $0.id == clip2 }?.effectiveDuration ?? 0) - 6.0667) < 0.001)

        let still = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let id = still.recipe.clips[1].id
        still.selectClip(id)
        still.beginFrameTrim(id, edge: .trailing)
        still.commitFrameTrim()
        #expect(!still.canUndo)
    }
}

extension VideoStudioFrameTrimTests {
    /// FS-12.17 AC-4: ✕ after −4 frames — the recipe exactly as before the
    /// hold, the undo depth unchanged (an earlier step in the clip's
    /// session stays where it was), the playhead back on the edge.
    @Test func cancelRestoresAndKeepsUndoDepth() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.pushUndo()
        model.setSpeed(1.5, for: clip2)    // a step of the clip's own session
        let before = model.recipe
        let checkpoint = model.history.checkpoint
        let newest = model.history.newestSequence
        model.beginFrameTrim(clip2, edge: .trailing)
        for _ in 0..<4 { model.stepFrameTrim(-1) }
        model.cancelFrameTrim()
        #expect(!model.isFrameTrimming)
        #expect(model.recipe == before)
        #expect(model.history.checkpoint == checkpoint)
        #expect(model.history.newestSequence == newest)
        #expect(model.selectedClipID == clip2)
        #expect(abs(model.currentTime - model.clipPlacements[1].end) < 1e-9)
        // ✕ of the clip after it still takes back the speed step.
        model.cancelSession()
        #expect(model.recipe.clips[1].speed == 1)
    }
}

extension VideoStudioFrameTrimTests {
    /// FS-12.17 AC-14: VoiceOver on Clip 2's end handle reads "Clip 2 end,
    /// 0:09.20"; one swipe down moves it a frame earlier — written at once,
    /// one undo step — and it reads "0:09.17".
    @Test func adjustableDecrementStepsOneFrame() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        #expect(VideoStudioCopy.edgeHandleName("Clip 2", trailing: true) == "Clip 2 end")
        #expect(model.clipEdgeTime(clip2, edge: .trailing).map(VideoFrameGrid.hundredths) == "0:09.20")
        #expect(model.stepClipEdge(clip2, edge: .trailing, by: -1))
        #expect(model.clipEdgeTime(clip2, edge: .trailing).map(VideoFrameGrid.hundredths) == "0:09.17")
        #expect(abs(model.recipe.clips[1].effectiveDuration - (6.2 - 1.0 / 30)) < 1e-9)
        #expect(model.canUndo)
        model.undo()
        #expect(model.clipEdgeTime(clip2, edge: .trailing).map(VideoFrameGrid.hundredths) == "0:09.20")
        // Clip 3 at the end of its source cannot go later.
        #expect(!model.stepClipEdge(model.recipe.clips[2].id, edge: .trailing, by: 1))
    }
}
