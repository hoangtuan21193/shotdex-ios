import Foundation

/// What a Video Studio key does (FS-12.17b §3) — the one place the keys
/// meet the model, so a test can press them without a keyboard. The
/// screen's layer and the iPad's menu bar both call it.
@MainActor
enum VideoKeyboardRouter {
    /// What the screen still has to do after a key.
    enum Outcome: Equatable {
        /// The model did it, or there was nothing to do.
        case done
        /// ⌘E: the screen opens the export, the way its Export button does.
        case openExport
    }

    /// Whether `shortcut` can act right now — the menu bar greys out the
    /// rest.
    static func isEnabled(_ shortcut: VideoShortcut, model: VideoStudioModel) -> Bool {
        switch shortcut {
        case .undo: model.canUndo
        case .redo: model.canRedo
        case .export: model.exportState == .idle
        case .deselect: model.presentsSheet || model.isFrameTrimming
        case .selectAll: model.mode == .multiClip && !model.recipe.clips.isEmpty
        case .trimStart, .trimEnd: !model.recipe.clips.isEmpty && !model.isLaneLocked(.video)
        case .delete: model.hasSelection
        default: true
        }
    }

    /// Runs `shortcut` on `model`.
    @discardableResult
    static func perform(_ shortcut: VideoShortcut, model: VideoStudioModel) -> Outcome {
        switch shortcut {
        case .playPause: model.togglePlayback()
        case .stop: model.shuttle(.k)
        case .playBackward: model.shuttle(.j)
        case .playForward, .faster: model.shuttle(.l)
        case .backSecond: model.seek(to: model.currentTime - 1)
        case .forwardSecond: model.seek(to: model.currentTime + 1)
        case .backFrame: model.stepFrames(-1)
        case .forwardFrame: model.stepFrames(1)
        case .goToStart: model.seek(to: 0)
        case .goToEnd: model.seek(to: model.totalDuration)
        case .split: model.splitClipUnderPlayhead()
        case .addMarker: model.addMarker()
        case .undo: model.undo()
        case .redo: model.redo()
        case .fitTimeline: model.fitToWindow()
        case .selectAll: model.selectAllClips()
        case .deselect: model.pressEscape()
        case .beforeAfter: model.toggleBeforeAfter(sideBySide: false)
        // The clip under the playhead, as the transport's buttons: a locked
        // video lane or a playhead on the clip's edge does nothing.
        case .trimStart: model.trimToPlayhead(.start)
        case .trimEnd: model.trimToPlayhead(.end)
        // The sheet, not the export: ⌘E puts the user where the Export
        // button does, it does not start writing to their library.
        case .delete: model.deleteSelection()
        case .export: return .openExport
        case .zoomIn, .zoomOut, .markIn, .markOut, .clearInOut:
            break
        }
        return .done
    }
}
