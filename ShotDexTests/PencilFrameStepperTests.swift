import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// Apple Pencil frame steps (FS-12.17 §8).
struct PencilFrameStepperTests {
    /// FS-12.17 AC-11: the Pencil rests 0.3 s on the edge, then goes 24pt
    /// left — exactly two frames earlier, whatever the zoom.
    @Test func stillThenTwentyFourPointsIsTwoFrames() {
        var stepper = PencilFrameStepper(x: 100, time: 0)
        stepper.sample(x: 100.5, time: 0.1)
        #expect(!stepper.isStepping)
        stepper.sample(x: 101, time: 0.31)
        #expect(stepper.isStepping)
        stepper.sample(x: 90, time: 0.5)
        #expect(stepper.steppedFrames(at: 101 - 24) == -2)
        #expect(stepper.steppedFrames(at: 101 - 23) == -1)
        // At 55pt a second, 30 fps, those two frames are 3.67pt of timeline.
        let translation = stepper.effectiveTranslation(from: 100, to: 101 - 24, pps: 55, fps: 30)
        #expect(abs(translation - (1 - 2 * 55.0 / 30)) < 0.001)
    }

    /// More than 2pt of drift starts the wait over.
    @Test func driftOverTwoPointsResetsStillness() {
        var stepper = PencilFrameStepper(x: 100, time: 0)
        stepper.sample(x: 103, time: 0.2)
        stepper.sample(x: 103, time: 0.4)
        #expect(!stepper.isStepping)
        stepper.sample(x: 104, time: 0.51)
        #expect(stepper.isStepping)
        // Before resting, the stroke is the stroke.
        let free = PencilFrameStepper(x: 50, time: 0)
        #expect(free.effectiveTranslation(from: 50, to: 80, pps: 55, fps: 30) == 30)
    }

    /// FS-12.17 AC-12: a double-tap toggles trim and scrub; in scrub the
    /// Pencil moves the playhead and Clip 2's window stays as it is.
    @MainActor
    @Test func scrubModeMovesPlayheadOnly() {
        #expect(PencilFrameStepper.Mode.trim.toggled == .scrub)
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.toggleFrameTrimFromCell()
        #expect(model.pencilMode == .trim)
        model.pencilDoubleTapped()
        #expect(model.pencilMode == .scrub)
        let window = (model.recipe.clips[1].trimStart, model.recipe.clips[1].trimEnd)
        model.scrub(to: 5)
        #expect(model.currentTime == 5)
        #expect(model.recipe.clips[1].trimStart == window.0 && model.recipe.clips[1].trimEnd == window.1)
        model.pencilDoubleTapped()
        #expect(model.pencilMode == .trim)
    }
}
