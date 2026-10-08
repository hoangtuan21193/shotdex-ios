import Foundation
import Testing
@testable import ShotDex

/// The 28 shortcuts (FS-12.17b §3–4).
struct VideoShortcutCatalogTests {
    /// FS-12.17b AC-10: 28 in three groups — Playback 11, Edit 10, View 7.
    @Test func twentyEightInThreeGroups() {
        #expect(VideoShortcut.allCases.count == 28)
        #expect(VideoShortcut.shortcuts(in: .playback).count == 11)
        #expect(VideoShortcut.shortcuts(in: .edit).count == 10)
        #expect(VideoShortcut.shortcuts(in: .view).count == 7)
    }

    /// The names as board F6_IL_Shortcuts writes them, group by group.
    @MainActor
    @Test func namesMatchBoard() {
        let board: [VideoShortcut.Group: [String]] = [
            .playback: ["Play or Pause", "Stop", "Play Backward", "Play Forward", "Faster",
                        "Back a Second", "Forward a Second", "Back a Frame", "Forward a Frame", "Go to Start", "Go to End"],
            .edit: ["Split at Playhead", "Mark In", "Mark Out", "Clear In and Out", "Trim Start to Playhead",
                    "Trim End to Playhead", "Delete", "Add Marker", "Undo", "Redo"],
            .view: ["Zoom In", "Zoom Out", "Fit Timeline", "Select All", "Deselect", "Before and After", "Export…"],
        ]
        for group in VideoShortcut.Group.allCases {
            #expect(VideoShortcut.shortcuts(in: group).map(VideoStudioCopy.shortcutName) == board[group])
        }
        #expect(VideoShortcut.split.keyLabel == "⌘B")
        #expect(VideoShortcut.backFrame.keyLabel == "⇧←")
        #expect(VideoShortcut.faster.keyLabel == "L L")
        #expect(VideoShortcut.redo.keyLabel == "⇧⌘Z")
        #expect(VideoShortcut.clearInOut.keyLabel == "⌥X")
        #expect(VideoShortcut.zoomOut.keyLabel == "⌘−")
        #expect(VideoShortcut.playPause.keyLabel == "Space")
    }

    /// No key runs two commands; only Faster has none of its own (it is
    /// L again).
    @Test func noTwoShareAKey() {
        let keys = VideoShortcut.allCases.compactMap(\.key)
        #expect(keys.count == 27)
        #expect(Set(keys).count == keys.count)
        #expect(VideoShortcut.faster.key == nil)
    }

    /// The phone's and the Duo's card: twelve rows, in the boards' order.
    @Test func compactListHasTwelveRowsInBoardOrder() {
        let rows = VideoShortcut.compactRows
        #expect(rows.count == 12)
        #expect(rows.first == [.playPause])
        #expect(rows[1] == [.playBackward, .stop, .playForward])
        #expect(rows.last == [.export])
        #expect(rows.flatMap { $0 }.count == Set(rows.flatMap { $0 }).count)
    }

    /// Bare keys — what has to stay silent while someone types (§3).
    @Test func bareKeysAreTheBoardsNine() {
        let bare = VideoShortcut.allCases.filter { $0.key?.isBare == true && $0.key?.input != .leftArrow && $0.key?.input != .rightArrow && $0.key?.input != .home && $0.key?.input != .end && $0.key?.input != .escape }
        #expect(Set(bare) == [.playPause, .playBackward, .stop, .playForward, .markIn, .markOut, .addMarker, .beforeAfter, .delete])
    }
}

/// The phone's and the Duo's card (FS-12.17b §4, AC-8).
extension VideoShortcutCatalogTests {
    /// The keycaps each folded row draws, as board F6_P_Keyboard does.
    @Test func keycapsMatchTheBoard() {
        let caps = VideoShortcut.compactRows.map(VideoShortcut.keycaps)
        #expect(caps == [
            ["Space"], ["J", "K", "L"], ["⇧", "←", "→"], ["⌘", "B"], ["I", "O"],
            ["⌥", "[", "]"], ["⌫"], ["M"], ["⌘", "Z", "⇧⌘Z"], ["⌘", "+", "−"], ["Esc"], ["⌘", "E"],
        ])
        #expect(VideoShortcut.compactRows.map(VideoStudioCopy.shortcutRowName) == [
            "Play or Pause", "Backward · Stop · Forward", "Back · Forward a Frame", "Split at Playhead",
            "Mark In · Out", "Trim Start · End to Playhead", "Delete", "Add Marker", "Undo · Redo",
            "Zoom In · Out", "Deselect", "Export…",
        ])
    }

    /// VoiceOver reads a row as its name and its keys.
    @Test func rowReadsNameThenKeys() {
        #expect(VideoStudioCopy.shortcutRowSpoken([.split]) == "Split at Playhead, Command B")
    }
}

/// When the card shows itself (FS-12.17b §4).
@MainActor
struct VideoShortcutListTests {
    private func preferences() -> VideoInputPreferences {
        let suite = "VideoShortcutListTests.\(UUID().uuidString)"
        return VideoInputPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    /// FS-12.17b AC-8: the first hardware key shows the list — once per
    /// install; the iPad never does. It takes the panel's place.
    @Test func firstKeyShowsTheListOnce() {
        let prefs = preferences()
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.noteHardwareKey(isIPad: false, preferences: prefs)
        #expect(model.isShortcutListShown)
        #expect(model.presentsSheet)
        VideoKeyboardRouter.perform(.deselect, model: model)
        #expect(!model.isShortcutListShown)
        model.noteHardwareKey(isIPad: false, preferences: prefs)
        #expect(!model.isShortcutListShown)
        // Holding ⌘ brings it back.
        model.showShortcutList()
        #expect(model.isShortcutListShown)

        let iPad = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        iPad.noteHardwareKey(isIPad: true, preferences: preferences())
        #expect(!iPad.isShortcutListShown)
    }
}
