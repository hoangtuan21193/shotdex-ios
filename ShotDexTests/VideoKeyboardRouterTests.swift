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

/// The keys' gate (FS-12.17b §3, AC-5): quiet while typing, silent under a
/// sheet.
@MainActor
struct VideoKeyboardGateTests {
    /// FS-12.17b AC-5: typing "jim k" in a text overlay — K does not stop
    /// the transport, I sets no In, Space does not play; ⌘ keys still work.
    @Test func bareKeysSilentWhileTyping() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.seek(to: 2)
        model.isTypingText = true
        for shortcut in [VideoShortcut.markIn, .stop, .playPause, .backSecond, .backFrame, .trimStart, .delete] {
            #expect(!VideoKeyboardRouter.isEnabled(shortcut, model: model), "\(shortcut)")
        }
        VideoKeyboardRouter.perform(.markIn, model: model)
        VideoKeyboardRouter.perform(.trimStart, model: model)
        #expect(model.recipe.inOutRange.isEmpty)
        #expect(!model.canUndo)
        #expect(model.currentTime == 2)
        // ⌘ keys still answer.
        #expect(VideoKeyboardRouter.isEnabled(.split, model: model))
        #expect(VideoKeyboardRouter.isEnabled(.export, model: model))
        model.isTypingText = false
        #expect(VideoKeyboardRouter.isEnabled(.markIn, model: model))
    }

    /// Under any sheet or alert, nothing — not even ⌘ keys.
    @Test func everythingSilentUnderSheet() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.seek(to: 7)
        model.nestedModalCount = 1
        for shortcut in VideoShortcut.allCases {
            #expect(!VideoKeyboardRouter.isEnabled(shortcut, model: model), "\(shortcut)")
        }
        VideoKeyboardRouter.perform(.split, model: model)
        #expect(model.recipe.clips.count == 3)
        model.nestedModalCount = 0
        #expect(!VideoKeyboardRouter.isEnabled(.split, model: model, screenModalIsUp: true))
        #expect(VideoKeyboardRouter.perform(.export, model: model, screenModalIsUp: true) == .done)
        model.errorMessage = "x"
        #expect(!VideoKeyboardRouter.isEnabled(.playPause, model: model))
    }
}

/// Esc, Return and ⇧←/⇧→ in the frame trim (FS-12.17b §3, AC-11).
@MainActor
struct VideoKeyboardTrimTests {
    private func trimmingModel() -> (VideoStudioModel, UUID) {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        let clip = model.recipe.clips[1].id
        #expect(model.beginFrameTrim(clip, edge: .trailing))
        return (model, clip)
    }

    /// ⇧← four times moves Clip 2's end four frames in — the edge, with
    /// the playhead on it; the recipe waits for ✓.
    @Test func shiftArrowsStepEdgeNotPlayhead() {
        let (model, _) = trimmingModel()
        let before = model.recipe
        for _ in 0..<4 { VideoKeyboardRouter.perform(.backFrame, model: model) }
        #expect(model.frameTrim?.frames == -4)
        #expect(abs(model.currentTime - (9.2 - 4.0 / 30)) < 1e-6)
        #expect(model.recipe == before)
        VideoKeyboardRouter.perform(.forwardFrame, model: model)
        #expect(model.frameTrim?.frames == -3)
    }

    /// FS-12.17b AC-11 and the order: Esc leaves the trim as ✕ (the recipe
    /// as before it, the clip still selected), then closes the shortcut
    /// list, then deselects.
    @Test func escapeOrder() {
        let (model, clip) = trimmingModel()
        let before = model.recipe
        for _ in 0..<4 { VideoKeyboardRouter.perform(.backFrame, model: model) }
        model.isShortcutListShown = true
        VideoKeyboardRouter.perform(.deselect, model: model)
        #expect(!model.isFrameTrimming)
        #expect(model.recipe == before)
        #expect(!model.canUndo)
        #expect(model.selectedClipID == clip)
        #expect(model.isShortcutListShown)
        VideoKeyboardRouter.perform(.deselect, model: model)
        #expect(!model.isShortcutListShown)
        #expect(model.selectedClipID == clip)
        VideoKeyboardRouter.perform(.deselect, model: model)
        #expect(model.selectedClipID == nil)
    }

    /// Return is ✓: the four frames become one undo step.
    @Test func returnCommitsTrim() {
        let (model, _) = trimmingModel()
        for _ in 0..<4 { VideoKeyboardRouter.perform(.backFrame, model: model) }
        #expect(VideoKeyboardRouter.returnIsEnabled(model: model))
        VideoKeyboardRouter.pressReturn(model: model)
        #expect(!model.isFrameTrimming)
        #expect(abs((model.recipe.clips[1].trimEnd ?? 0) - (6.2 - 4.0 / 30)) < 1e-6)
        #expect(model.canUndo)
        // While typing, Return is the field's.
        model.isTypingText = true
        #expect(!VideoKeyboardRouter.returnIsEnabled(model: model))
    }
}

/// Holding ⌘ (FS-12.17b §4, AC-9; plan decision 11).
@MainActor
struct VideoKeyboardHoldTests {
    /// The Duo's inner display: ⌘ held 0.6 s shows the card, letting go
    /// hides it. Shown on its own the first time, it stays until a tap
    /// outside or Esc. The phone's list stays when ⌘ is let go.
    @Test func holdOpensAfter600ms() {
        #expect(VideoSystemKeyResponder.commandHoldDelay == .milliseconds(600))
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.shortcutListIsOverlay = true
        model.commandHoldBegan()
        #expect(model.isShortcutListShown)
        #expect(!model.presentsSheet)          // a card over the studio, not a panel
        model.commandHoldEnded()
        #expect(!model.isShortcutListShown)

        let prefs = VideoInputPreferences(defaults: UserDefaults(suiteName: "hold.\(UUID().uuidString)")!)
        model.noteHardwareKey(isIPad: false, preferences: prefs)
        #expect(model.isShortcutListShown)
        model.commandHoldBegan()
        model.commandHoldEnded()
        #expect(model.isShortcutListShown)     // not opened by the hold
        model.pressEscape()
        #expect(!model.isShortcutListShown)

        let phone = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        phone.commandHoldBegan()
        phone.commandHoldEnded()
        #expect(phone.isShortcutListShown)
        #expect(phone.presentsSheet)
    }
}
