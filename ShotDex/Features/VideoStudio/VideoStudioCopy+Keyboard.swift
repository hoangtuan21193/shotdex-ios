import Foundation

/// Words of the keyboard (FS-12.17b): the 28 shortcuts' names as the boards
/// write them, their groups, the card's folded rows.
extension VideoStudioCopy {
    /// The In–Out flags on the ruler (FS-12.17b §5), for VoiceOver.
    static var inPointLabel: String {
        String(localized: "In Point", table: table, comment: "Video Studio ruler: the In flag of the In–Out range (VoiceOver)")
    }

    static var outPointLabel: String {
        String(localized: "Out Point", table: table, comment: "Video Studio ruler: the Out flag of the In–Out range (VoiceOver)")
    }

    static func shortcutName(_ shortcut: VideoShortcut) -> String {
        switch shortcut {
        case .playPause: String(localized: "Play or Pause", table: table, comment: "Video Studio keyboard shortcut (Space)")
        case .stop: String(localized: "Stop", table: table, comment: "Video Studio keyboard shortcut (K)")
        case .playBackward: String(localized: "Play Backward", table: table, comment: "Video Studio keyboard shortcut (J)")
        case .playForward: String(localized: "Play Forward", table: table, comment: "Video Studio keyboard shortcut (L)")
        case .faster: String(localized: "Faster", table: table, comment: "Video Studio keyboard shortcut (L pressed again: 2×, 4×)")
        case .backSecond: String(localized: "Back a Second", table: table, comment: "Video Studio keyboard shortcut (←)")
        case .forwardSecond: String(localized: "Forward a Second", table: table, comment: "Video Studio keyboard shortcut (→)")
        case .backFrame: String(localized: "Back a Frame", table: table, comment: "Video Studio keyboard shortcut (⇧←)")
        case .forwardFrame: String(localized: "Forward a Frame", table: table, comment: "Video Studio keyboard shortcut (⇧→)")
        case .goToStart: String(localized: "Go to Start", table: table, comment: "Video Studio keyboard shortcut (Home)")
        case .goToEnd: String(localized: "Go to End", table: table, comment: "Video Studio keyboard shortcut (End)")
        case .split: String(localized: "Split at Playhead", table: table, comment: "Video Studio keyboard shortcut (⌘B)")
        case .markIn: String(localized: "Mark In", table: table, comment: "Video Studio keyboard shortcut (I)")
        case .markOut: String(localized: "Mark Out", table: table, comment: "Video Studio keyboard shortcut (O)")
        case .clearInOut: String(localized: "Clear In and Out", table: table, comment: "Video Studio keyboard shortcut (⌥X)")
        case .trimStart: String(localized: "Trim Start to Playhead", table: table, comment: "Video Studio keyboard shortcut (⌥[)")
        case .trimEnd: String(localized: "Trim End to Playhead", table: table, comment: "Video Studio keyboard shortcut (⌥])")
        case .delete: String(localized: "Delete", table: table, comment: "Video Studio keyboard shortcut (⌫): deletes what is selected")
        case .addMarker: String(localized: "Add Marker", table: table, comment: "Video Studio keyboard shortcut (M)")
        case .undo: String(localized: "Undo", table: table, comment: "Video Studio keyboard shortcut (⌘Z)")
        case .redo: String(localized: "Redo", table: table, comment: "Video Studio keyboard shortcut (⇧⌘Z)")
        case .zoomIn: String(localized: "Zoom In", table: table, comment: "Video Studio keyboard shortcut (⌘+): the timeline")
        case .zoomOut: String(localized: "Zoom Out", table: table, comment: "Video Studio keyboard shortcut (⌘−): the timeline")
        case .fitTimeline: String(localized: "Fit Timeline", table: table, comment: "Video Studio keyboard shortcut (⇧Z)")
        case .selectAll: String(localized: "Select All", table: table, comment: "Video Studio keyboard shortcut (⌘A): every clip")
        case .deselect: String(localized: "Deselect", table: table, comment: "Video Studio keyboard shortcut (Esc)")
        case .beforeAfter: String(localized: "Before and After", table: table, comment: "Video Studio keyboard shortcut (\\)")
        case .export: String(localized: "Export…", table: table, comment: "Video Studio keyboard shortcut (⌘E): opens Export, does not export")
        }
    }

    // MARK: The Text panel (phone, Duo — FS-12.04 §3)

    static var textPanelTitle: String {
        String(localized: "Text", table: table, comment: "Video Studio: title of the Text tool's panel on the phone and the Duo")
    }

    static var addText: String {
        String(localized: "Add Text", table: table, comment: "Video Studio: adds a caption block at the playhead in the last-used font")
    }

    // MARK: Skim (iPad — FS-12.17b §6)

    static var skimming: String {
        String(localized: "Skimming", table: table, comment: "Video Studio iPad: under the frame while the pointer skims a library video — Skimming · Lake · 0:02.3 / 0:05")
    }

    static var notDownloaded: String {
        String(localized: "Not downloaded", table: table, comment: "Video Studio iPad skim: the video is only in iCloud, so the frame shows its thumbnail")
    }

    static var skimHint: String {
        String(localized: "Click adds · drag to place", table: table, comment: "Video Studio iPad: under the library cell the pointer skims — a click adds it at the playhead, a drag places it")
    }

    // MARK: The card (phone, Duo — FS-12.17b §4)

    static var keyboardShortcutsTitle: String {
        String(localized: "Keyboard Shortcuts", table: table, comment: "Video Studio: title of the card that lists the keyboard shortcuts (phone, Duo)")
    }

    static var keyboardConnected: String {
        String(localized: "Keyboard connected", table: table, comment: "Video Studio keyboard card: a hardware keyboard is attached")
    }

    static var holdCommandHint: String {
        String(localized: "hold ⌘ for this list", table: table, comment: "Video Studio keyboard card: holding the Command key brings the list back")
    }

    static var holdCommandAgainHint: String {
        String(localized: "Hold ⌘ to see these again", table: table, comment: "Video Studio keyboard card on the Duo's inner display: subtitle under the title")
    }

    /// A folded row's name, as the boards write it.
    static func shortcutRowName(_ row: [VideoShortcut]) -> String {
        guard row.count > 1, let first = row.first else { return row.first.map(shortcutName) ?? "" }
        switch first {
        case .playBackward: return String(localized: "Backward · Stop · Forward", table: table, comment: "Video Studio keyboard card row: J, K, L")
        case .backFrame: return String(localized: "Back · Forward a Frame", table: table, comment: "Video Studio keyboard card row: Shift-Left, Shift-Right")
        case .markIn: return String(localized: "Mark In · Out", table: table, comment: "Video Studio keyboard card row: I, O")
        case .trimStart: return String(localized: "Trim Start · End to Playhead", table: table, comment: "Video Studio keyboard card row: Option-[, Option-]")
        case .undo: return String(localized: "Undo · Redo", table: table, comment: "Video Studio keyboard card row: Command-Z, Shift-Command-Z")
        case .zoomIn: return String(localized: "Zoom In · Out", table: table, comment: "Video Studio keyboard card row: Command-+, Command-−")
        default: return row.map(shortcutName).joined(separator: " · ")
        }
    }

    /// What VoiceOver reads for a row: "Split at Playhead, Command B".
    static func shortcutRowSpoken(_ row: [VideoShortcut]) -> String {
        let keys = row.compactMap(\.key).map(spokenKey).joined(separator: ", ")
        return shortcutRowName(row) + ", " + keys
    }

    static func spokenKey(_ key: VideoShortcut.Key) -> String {
        let modifiers = key.modifiers.sorted().map { modifier -> String in
            switch modifier {
            case .control: String(localized: "Control", table: table, comment: "VoiceOver: the Control key")
            case .option: String(localized: "Option", table: table, comment: "VoiceOver: the Option key")
            case .shift: String(localized: "Shift", table: table, comment: "VoiceOver: the Shift key")
            case .command: String(localized: "Command", table: table, comment: "VoiceOver: the Command key")
            }
        }
        let input: String = switch key.input {
        case .character("="): "+"
        case .character("-"): "−"
        case .character(let character): String(character).uppercased()
        case .space: String(localized: "Space", table: table, comment: "VoiceOver: the Space bar")
        case .escape: String(localized: "Escape", table: table, comment: "VoiceOver: the Escape key")
        case .delete: String(localized: "Delete", table: table, comment: "VoiceOver: the Delete key")
        case .returnKey: String(localized: "Return", table: table, comment: "VoiceOver: the Return key")
        case .leftArrow: String(localized: "Left Arrow", table: table, comment: "VoiceOver: the Left Arrow key")
        case .rightArrow: String(localized: "Right Arrow", table: table, comment: "VoiceOver: the Right Arrow key")
        case .home: String(localized: "Home", table: table, comment: "VoiceOver: the Home key")
        case .end: String(localized: "End", table: table, comment: "VoiceOver: the End key")
        }
        return (modifiers + [input]).joined(separator: " ")
    }

    static func shortcutGroupName(_ group: VideoShortcut.Group) -> String {
        switch group {
        case .playback: String(localized: "Playback", table: table, comment: "Video Studio keyboard shortcuts: the group of play, stop and stepping keys")
        case .edit: String(localized: "Edit", table: table, comment: "Video Studio keyboard shortcuts: the group of editing keys")
        case .view: String(localized: "View", table: table, comment: "Video Studio keyboard shortcuts: the group of zoom, selection and export keys")
        }
    }
}
