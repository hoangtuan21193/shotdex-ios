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

extension VideoEdgeTrimMathTests {
    /// FS-12.05 AC-4: a 3 s photo dragged 2.8 s in stops at 0.5 s; out, at 10.
    @Test func photoEdgeClampsAtHalfASecond() {
        let still = VideoStudioModelFixture.photoClips(1, seconds: 3)[0]
        let shorter = VideoEdgeTrimMath.drag(still, edge: .leading, by: 2.8)
        #expect(shorter.photoDuration == 0.5)
        #expect(shorter.duration == 0.5)
        #expect(shorter.hitLimit)
        let longer = VideoEdgeTrimMath.drag(still, edge: .trailing, by: 9)
        #expect(longer.photoDuration == 10)
        #expect(longer.hitLimit)
    }
}

extension VideoEdgeTrimModelTests {
    /// FS-12.05 AC-8: within 8pt of a marker the dragged edge sticks to it
    /// (one tick); it never sticks to where it started.
    @Test func edgeSnapsToAMarkerWithinEightPoints() {
        let model = VideoStudioModelFixture.model { $0.markers = [TimedMarker(time: 13)] }
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        let tolerance = 8.0 / 40.0   // 8pt at 40 points per second

        let near = model.edgeTrim(clip2, edge: .leading, phase: .changed(2.9), snapTolerance: tolerance)
        #expect(near.snapped)
        #expect(model.edgeTrimPreview?.result.trimStart == 3)
        model.edgeTrim(clip2, edge: .leading, phase: .ended(2.9), snapTolerance: tolerance)
        #expect(model.recipe.clips[1].trimStart == 3)

        // A small drag next to the clip's own starting edge does not stick
        // back to it.
        let own = model.edgeTrim(clip2, edge: .trailing, phase: .changed(-0.05), snapTolerance: tolerance)
        #expect(!own.snapped)
        model.edgeTrim(clip2, edge: .trailing, phase: .cancelled)
    }
}

extension VideoEdgeTrimModelTests {
    /// FS-12.05 AC-9: an edge cut, then ✕ — the clip is 0–10 again and
    /// Redo has nothing.
    @Test func cancelUndoesAnEdgeTrim() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.edgeTrim(clip2, edge: .leading, phase: .changed(2))
        model.edgeTrim(clip2, edge: .leading, phase: .ended(2))
        #expect(model.recipe.clips[1].trimStart == 2)

        model.cancelSession()
        #expect(model.recipe.clips[1].trimStart == 0)
        #expect(model.recipe.clips[1].trimEnd == 10)
        #expect(!model.canRedo)
        #expect(!model.canUndo)
    }

    /// FS-12.05 AC-10: the system takes the touch mid-drag (a call) —
    /// nothing changes, no undo step, the playhead is where it was.
    @Test func cancelledDragChangesNothing() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.seek(to: 6)
        let before = model.recipe
        model.edgeTrim(clip2, edge: .trailing, phase: .changed(-3))
        #expect(model.edgeTrimPreview != nil)
        model.edgeTrim(clip2, edge: .trailing, phase: .cancelled)
        #expect(model.recipe == before)
        #expect(model.edgeTrimPreview == nil)
        #expect(!model.canUndo)
        #expect(model.currentTime == 6)
    }
}
