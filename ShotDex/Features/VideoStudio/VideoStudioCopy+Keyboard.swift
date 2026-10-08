import Foundation

/// Words of the keyboard (FS-12.17b): the 28 shortcuts' names as the boards
/// write them, their groups, the card's folded rows.
extension VideoStudioCopy {
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

    static func shortcutGroupName(_ group: VideoShortcut.Group) -> String {
        switch group {
        case .playback: String(localized: "Playback", table: table, comment: "Video Studio keyboard shortcuts: the group of play, stop and stepping keys")
        case .edit: String(localized: "Edit", table: table, comment: "Video Studio keyboard shortcuts: the group of editing keys")
        case .view: String(localized: "View", table: table, comment: "Video Studio keyboard shortcuts: the group of zoom, selection and export keys")
        }
    }
}
