import Foundation
import Testing
@testable import ShotDex

/// The In–Out range's rules (FS-12.17b §5).
struct VideoInOutRangeTests {
    /// O before In: In goes back to 0.
    @Test func outBeforeInResetsIn() {
        let range = VideoInOutRange(inPoint: 8)
            .markingOut(at: 5, totalDuration: 24)
        #expect(range == VideoInOutRange(inPoint: 0, outPoint: 5))
    }

    /// I after Out: Out is cleared.
    @Test func inAfterOutClearsOut() {
        let range = VideoInOutRange(outPoint: 12)
            .markingIn(at: 14, totalDuration: 24)
        #expect(range == VideoInOutRange(inPoint: 14, outPoint: nil))
        // I before Out keeps it.
        let kept = VideoInOutRange(outPoint: 12).markingIn(at: 5, totalDuration: 24)
        #expect(kept == VideoInOutRange(inPoint: 5, outPoint: 12))
    }

    /// FS-12.17b AC-3: In 5.0, Out 12.0 — Loop turns back at 12.0 to 5.0;
    /// Play outside the range starts at In; with no range, 0 to the end.
    @Test func loopTargetIsIn() {
        let range = VideoInOutRange(inPoint: 5, outPoint: 12)
        #expect(range.loopStart == 5)
        #expect(range.loopEnd(totalDuration: 24) == 12)
        #expect(range.loopPlayStart(from: 8.4, totalDuration: 24) == 8.4)
        #expect(range.loopPlayStart(from: 2, totalDuration: 24) == 5)
        #expect(range.loopPlayStart(from: 12, totalDuration: 24) == 5)
        #expect(range.loopPlayStart(from: 20, totalDuration: 24) == 5)
        let none = VideoInOutRange()
        #expect(none.loopStart == 0 && none.loopEnd(totalDuration: 24) == 24)
    }

    /// Marks land inside the project.
    @Test func marksAreClampedToTheProject() {
        #expect(VideoInOutRange().markingIn(at: -1, totalDuration: 24).inPoint == 0)
        #expect(VideoInOutRange().markingOut(at: 30, totalDuration: 24).outPoint == 24)
    }
}

/// The In–Out range in the model (FS-12.17b §5, plan decision 7).
@MainActor
struct VideoStudioInOutTests {
    private func model() -> VideoStudioModel {
        let recipe = VideoStudioModelFixture.mediaSampleRecipe()
        return VideoStudioModelFixture.model(clips: recipe.clips, configure: { $0 = recipe })
    }

    /// FS-12.17b AC-3 (keys): I at 5.0, O at 12.0; ⌥X clears both. No undo
    /// step for any of them.
    @Test func keysMarkAndClear() {
        let model = model()
        model.seek(to: 5)
        VideoKeyboardRouter.perform(.markIn, model: model)
        model.seek(to: 12)
        VideoKeyboardRouter.perform(.markOut, model: model)
        #expect(model.recipe.inOutRange == VideoInOutRange(inPoint: 5, outPoint: 12))
        #expect(!model.canUndo)
        #expect(VideoKeyboardRouter.isEnabled(.clearInOut, model: model))
        VideoKeyboardRouter.perform(.clearInOut, model: model)
        #expect(model.recipe.inOutRange.isEmpty)
        #expect(!VideoKeyboardRouter.isEnabled(.clearInOut, model: model))
    }

    /// Undo of a cut keeps the In just set: the range is not part of any
    /// step.
    @Test func undoKeepsInOut() {
        let model = model()
        model.seek(to: 7)
        model.splitClipUnderPlayhead()
        model.seek(to: 5)
        model.markIn()
        model.seek(to: 12)
        model.markOut()
        model.undo()
        #expect(model.recipe.clips.count == 5)
        #expect(model.recipe.inOutRange == VideoInOutRange(inPoint: 5, outPoint: 12))
        model.redo()
        #expect(model.recipe.clips.count == 6)
        #expect(model.recipe.inOutRange == VideoInOutRange(inPoint: 5, outPoint: 12))
    }

    /// The draft keeps the range, and a project reopened from it has it.
    @Test func inOutIsSavedWithTheDraft() throws {
        let model = model()
        model.seek(to: 5)
        model.markIn()
        model.seek(to: 12)
        model.markOut()
        let reopened = try #require(try model.draftSnapshot().videoRecipe)
        #expect(reopened.inPoint == 5 && reopened.outPoint == 12)
    }

    /// A project written before the range existed opens with none — and the
    /// rest of it as it was.
    @Test func decodesWithoutTheKeys() throws {
        var recipe = VideoStudioModelFixture.mediaSampleRecipe()
        recipe.inPoint = 5
        recipe.outPoint = 12
        let data = try JSONEncoder().encode(recipe)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["inPoint"] != nil)
        object.removeValue(forKey: "inPoint")
        object.removeValue(forKey: "outPoint")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(VideoProjectRecipe.self, from: old)
        #expect(decoded.inPoint == nil && decoded.outPoint == nil)
        #expect(decoded.clips.count == recipe.clips.count)
    }
}

/// Go to Start / Go to End and Home / End follow the range (FS-12.17b
/// AC-16).
@MainActor
struct VideoInOutGoToTests {
    private func model() -> VideoStudioModel {
        let recipe = VideoStudioModelFixture.mediaSampleRecipe()
        return VideoStudioModelFixture.model(clips: recipe.clips, configure: { $0 = recipe })
    }

    /// FS-12.17b AC-16: In 5.0, Out 12.0, playhead 8.4 — Home 5.0, End 12.0.
    @Test func homeGoesToInEndToOut() {
        let model = model()
        model.seek(to: 5)
        model.markIn()
        model.seek(to: 12)
        model.markOut()
        model.seek(to: 8.4)
        VideoKeyboardRouter.perform(.goToStart, model: model)
        #expect(model.currentTime == 5)
        VideoKeyboardRouter.perform(.goToEnd, model: model)
        #expect(model.currentTime == 12)
    }

    /// Only an In: End goes to the project's end. Only an Out: Home goes
    /// to 0.
    @Test func onlyInMeansEndIsProjectEnd() {
        let model = model()
        model.seek(to: 5)
        model.markIn()
        model.goToEnd()
        #expect(abs(model.currentTime - 24) < 1e-9)
        #expect(VideoInOutRange(outPoint: 12).goToStartTarget == 0)
        #expect(VideoInOutRange(outPoint: 12).goToEndTarget(totalDuration: 24) == 12)
    }

    /// FS-12.17b AC-16: ⌥X, then Home — 0.0.
    @Test func clearedHomeIsZero() {
        let model = model()
        model.seek(to: 5)
        model.markIn()
        model.seek(to: 12)
        model.markOut()
        model.seek(to: 8.4)
        VideoKeyboardRouter.perform(.clearInOut, model: model)
        VideoKeyboardRouter.perform(.goToStart, model: model)
        #expect(model.currentTime == 0)
    }
}
