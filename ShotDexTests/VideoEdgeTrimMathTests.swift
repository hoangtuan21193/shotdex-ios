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
