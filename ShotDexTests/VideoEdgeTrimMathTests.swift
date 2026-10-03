import Foundation
import Testing
@testable import ShotDex

/// Dragging a clip's edge (FS-12.05 §3).
struct VideoEdgeTrimMathTests {
    private func video(seconds: Double = 10, speed: Double = 1) -> VideoClip {
        var clip = VideoStudioModelFixture.videoClips(1, seconds: seconds)[0]
        clip.speed = speed
        return clip
    }

    /// FS-12.05 AC-1: the leading handle dragged 2.0 s in — source 2–10.
    @Test func leadingDragMovesTheSourceInPoint() {
        let result = VideoEdgeTrimMath.drag(video(), edge: .leading, by: 2)
        #expect(result.trimStart == 2)
        #expect(result.trimEnd == 10)
        #expect(result.duration == 8)
        #expect(!result.hitLimit)
    }
}

/// The edge drag through the model (FS-12.05 §3).
@MainActor
struct VideoEdgeTrimModelTests {
    /// FS-12.05 AC-1: clip 2's leading handle dragged 2.0 s in — source
    /// 2–10, clip 3 starts 2.0 s earlier, one undo step, playhead back.
    @Test func leadingDragTrimsAndPullsTheNextClipIn() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.seek(to: 5)
        #expect(model.clipPlacements[2].start == 20)

        model.edgeTrim(clip2, edge: .leading, phase: .changed(1))
        #expect(model.edgeTrimPreview?.result.trimStart == 1)
        model.edgeTrim(clip2, edge: .leading, phase: .changed(2))
        model.edgeTrim(clip2, edge: .leading, phase: .ended(2))

        #expect(model.recipe.clips[1].trimStart == 2)
        #expect(model.recipe.clips[1].trimEnd == 10)
        #expect(model.clipPlacements[2].start == 18)
        #expect(model.history.undoEntries.count == 1)
        #expect(model.edgeTrimPreview == nil)
        #expect(model.currentTime == 5)
        model.undo()
        #expect(model.recipe.clips[1].trimStart == 0)
    }
}

extension VideoEdgeTrimMathTests {
    /// FS-12.05 AC-2: a 2× clip's trailing handle dragged 1 s in — the
    /// source out-point goes 10 → 8 and the clip lasts 4 s.
    @Test func trailingDragConvertsThroughSpeed() {
        let result = VideoEdgeTrimMath.drag(video(speed: 2), edge: .trailing, by: -1)
        #expect(result.trimStart == 0)
        #expect(result.trimEnd == 8)
        #expect(result.duration == 4)
        #expect(!result.hitLimit)
    }
}

extension VideoEdgeTrimMathTests {
    /// FS-12.05 AC-3: dragged out past the source — it stops at the
    /// source's 10 s and reports the limit (the view's one light tick).
    @Test func dragPastTheSourceStopsAndReportsTheLimit() {
        var clip = video()
        clip.trimEnd = 8
        let result = VideoEdgeTrimMath.drag(clip, edge: .trailing, by: 5)
        #expect(result.trimEnd == 10)
        #expect(result.hitLimit)
        let before = VideoEdgeTrimMath.drag(clip, edge: .leading, by: -3)
        #expect(before.trimStart == 0)
        #expect(before.hitLimit)
        #expect(!VideoEdgeTrimMath.drag(clip, edge: .trailing, by: 1).hitLimit)
    }
}
