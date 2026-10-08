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
