import Foundation
import Testing
@testable import ShotDex

/// Trim Start / End to Playhead (FS-12.05 §3, FS-12.17b AC-4): the math is
/// `VideoClipTrimMath.trimToPlayhead` — one function for the transport's
/// buttons, the panel's chips and the ⌥[ / ⌥] keys (task 24).
struct VideoTrimToPlayheadTests {
    /// FS-12.17b AC-4: playhead 7.0 s, inside Clip 2 (it starts at 3.0 s) —
    /// Start to Playhead starts its source at 4.0 s and leaves it 2.2 s long.
    @Test func startAtSevenSecondsInClipTwo() {
        let clip2 = VideoStudioModelFixture.frameTrimSampleClips()[1]
        let outcome = VideoClipTrimMath.trimToPlayhead(clip2, end: .start, localTime: 7 - 3)
        guard case .trim(let start, let end) = outcome else {
            Issue.record("expected a trim, got \(outcome)")
            return
        }
        #expect(abs(start - 4) < 1e-9)
        #expect(abs(end - 6.2) < 1e-9)
        #expect(abs((end - start) - 2.2) < 1e-9)
    }

    /// A 2× clip: 2.0 s of timeline into it is 4.0 s into its source, so the
    /// local delta is halved on screen and doubled in the source.
    @Test func speedTwoHalvesTheLocalDelta() {
        var clip2 = VideoStudioModelFixture.frameTrimSampleClips()[1]
        clip2.speed = 2
        #expect(abs(clip2.effectiveDuration - 3.1) < 1e-9)
        let outcome = VideoClipTrimMath.trimToPlayhead(clip2, end: .start, localTime: 2)
        #expect(outcome == .trim(start: 4, end: 6.2))
    }

    /// On the clip's own edge, past it, or leaving less than a clip may be:
    /// nothing to cut.
    @Test func edgeOrBelowMinimumDoesNothing() {
        let clip2 = VideoStudioModelFixture.frameTrimSampleClips()[1]
        #expect(VideoClipTrimMath.trimToPlayhead(clip2, end: .start, localTime: 0) == .unavailable(.playheadOutsideClip))
        #expect(VideoClipTrimMath.trimToPlayhead(clip2, end: .end, localTime: 6.2) == .unavailable(.playheadOutsideClip))
        #expect(VideoClipTrimMath.trimToPlayhead(clip2, end: .start, localTime: 6.2 - 0.05) == .unavailable(.tooShort))
    }

    /// Through the model: Clip 2 under the playhead at 7.0 s, one undo step
    /// — and Undo puts the 0.0–6.2 window back.
    @MainActor
    @Test func theModelAddsOneUndoStep() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        #expect(!model.canUndo)
        model.seek(to: 7)
        model.trimToPlayhead(.start)
        #expect(abs(model.recipe.clips[1].trimStart - 4) < 1e-9)
        #expect(abs(model.recipe.clips[1].effectiveDuration - 2.2) < 1e-9)
        #expect(model.canUndo)
        model.undo()
        #expect(model.recipe.clips[1].trimStart == 0)
        #expect(model.recipe.clips[1].trimEnd == 6.2)
        #expect(!model.canUndo)
    }
}
