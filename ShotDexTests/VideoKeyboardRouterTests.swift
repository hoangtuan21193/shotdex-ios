import Foundation
import Testing
@testable import ShotDex

/// The Video Studio's keys pressed through `VideoKeyboardRouter` — the
/// function both the key layer and the iPad's menu bar call (FS-12.17b §3).
@MainActor
struct VideoKeyboardRouterTests {
    /// FS-12.17b AC-4 by key: playhead 7.0 s inside Clip 2 (it starts at
    /// 3.0 s); ⌥[ starts its source at 4.0 s, leaves it 2.2 s long, and is
    /// one undo step. ⌥] cuts the tail of the clip under the playhead.
    @Test func optionBracketTrimsClipUnderPlayhead() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.seek(to: 7)
        #expect(VideoKeyboardRouter.isEnabled(.trimStart, model: model))
        VideoKeyboardRouter.perform(.trimStart, model: model)
        #expect(abs(model.recipe.clips[1].trimStart - 4) < 1e-9)
        #expect(abs(model.recipe.clips[1].effectiveDuration - 2.2) < 1e-9)
        model.undo()
        #expect(model.recipe.clips[1].trimStart == 0)
        #expect(!model.canUndo)

        model.seek(to: 7)
        VideoKeyboardRouter.perform(.trimEnd, model: model)
        #expect(abs((model.recipe.clips[1].trimEnd ?? 0) - 4) < 1e-9)
        #expect(model.recipe.clips[1].trimStart == 0)
    }

    /// A locked video lane: the keys are greyed out and pressing them
    /// changes nothing.
    @Test func lockedLaneIgnoresOptionBracket() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.toggleLaneLock(.video)
        model.seek(to: 7)
        let before = model.recipe
        #expect(!VideoKeyboardRouter.isEnabled(.trimStart, model: model))
        VideoKeyboardRouter.perform(.trimStart, model: model)
        VideoKeyboardRouter.perform(.trimEnd, model: model)
        #expect(model.recipe == before)
        #expect(!model.canUndo)
    }

    /// ⌘E opens the export the way the Export button does; the router only
    /// says so.
    @Test func commandEAsksTheScreenToOpenTheExport() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        #expect(VideoKeyboardRouter.perform(.export, model: model) == .openExport)
    }
}

/// ⌫ (FS-12.17b AC-6): what is selected goes; nothing selected, nothing.
@MainActor
struct VideoKeyboardDeleteTests {
    /// FS-12.17b AC-6: nothing selected — the recipe does not change and
    /// no undo step is left.
    @Test func deleteWithoutSelectionDoesNothing() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.seek(to: 7)
        let before = model.recipe
        #expect(!VideoKeyboardRouter.isEnabled(.delete, model: model))
        VideoKeyboardRouter.perform(.delete, model: model)
        #expect(model.recipe == before)
        #expect(!model.canUndo)
    }

    /// A selected clip goes, as one undo step; the clip under the playhead
    /// is not what ⌫ deletes.
    @Test func deleteRemovesTheSelectedClip() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let first = model.recipe.clips[0].id
        model.seek(to: 7)
        model.selectClip(first)
        VideoKeyboardRouter.perform(.delete, model: model)
        #expect(!model.recipe.clips.contains { $0.id == first })
        #expect(model.recipe.clips.count == 2)
        model.undo()
        #expect(model.recipe.clips.count == 3)
    }

    /// Locking the video lane drops its selection, so ⌫ has nothing to take.
    @Test func lockedLaneKeepsTheSelectedClip() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.selectClip(model.recipe.clips[0].id)
        model.toggleLaneLock(.video)
        let before = model.recipe
        VideoKeyboardRouter.perform(.delete, model: model)
        #expect(model.recipe == before)
    }
}
