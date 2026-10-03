import Foundation
import Testing
@testable import ShotDex

/// Trim → Start/End to Playhead (FS-12.05 §3).
struct VideoClipTrimMathTests {
    private func video(seconds: Double = 10, speed: Double = 1) -> VideoClip {
        var clip = VideoStudioModelFixture.videoClips(1, seconds: seconds)[0]
        clip.speed = speed
        return clip
    }

    /// FS-12.05 AC-5: a 0–10 s clip, playhead 4 s in — Start to Playhead
    /// keeps 4–10, a 6.0 s clip.
    @Test func startToPlayheadKeepsTheTail() {
        let outcome = VideoClipTrimMath.trimToPlayhead(video(), end: .start, localTime: 4)
        #expect(outcome == .trim(start: 4, end: 10))
        var trimmed = video()
        trimmed.trimStart = 4
        #expect(trimmed.effectiveDuration == 6)
        #expect(VideoClipTrimMath.trimToPlayhead(video(), end: .end, localTime: 4) == .trim(start: 0, end: 4))
    }

    /// The model applies it to the selected clip as one undo step.
    @MainActor
    @Test func startToPlayheadOnTheSelectedClipUndoesOnce() {
        let model = VideoStudioModelFixture.model()
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.seek(to: 14)   // clip 2 runs 10–20
        #expect(model.trimSelectedClipToPlayhead(.start) == nil)
        #expect(model.recipe.clips[1].trimStart == 4)
        #expect(model.recipe.clips[1].trimEnd == 10)
        model.undo()
        #expect(model.recipe.clips[1].trimStart == 0)
        #expect(model.recipe.clips[1].trimEnd == 10)
    }
}
