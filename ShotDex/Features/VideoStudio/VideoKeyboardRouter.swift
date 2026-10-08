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

    /// Whether a key reaches the studio at all (§3): nothing under a sheet
    /// or an alert; while something is being typed in, only keys with ⌘ —
    /// a bare key, ⇧ or ⌥ is text or text editing ("k", "“", ⇧← to select).
    /// `screenModalIsUp`: one of the screen's own sheets or alerts is up.
    static func passesGate(_ shortcut: VideoShortcut, model: VideoStudioModel, screenModalIsUp: Bool = false) -> Bool {
        if screenModalIsUp || model.nestedModalCount > 0
            || model.editingTransitionIndex != nil || model.errorMessage != nil {
            return false
        }
        if model.isTypingText {
            return shortcut.key?.modifiers.contains(.command) == true
        }
        return true
    }

    /// Whether `shortcut` can act right now — the layer leaves the rest
    /// unregistered, so the key goes where it would without the studio,
    /// and the menu bar greys them out.
    static func isEnabled(_ shortcut: VideoShortcut, model: VideoStudioModel, screenModalIsUp: Bool = false) -> Bool {
        guard passesGate(shortcut, model: model, screenModalIsUp: screenModalIsUp) else { return false }
        return isAvailable(shortcut, model: model)
    }

    private static func isAvailable(_ shortcut: VideoShortcut, model: VideoStudioModel) -> Bool {
        switch shortcut {
        case .undo: model.canUndo
        case .redo: model.canRedo
        case .export: model.exportState == .idle
        case .deselect: model.presentsSheet || model.isFrameTrimming
        case .selectAll: model.mode == .multiClip && !model.recipe.clips.isEmpty
        case .trimStart, .trimEnd: !model.recipe.clips.isEmpty && !model.isLaneLocked(.video)
        case .delete: model.hasSelection
        case .clearInOut: !model.recipe.inOutRange.isEmpty
        default: true
        }
    }

    /// Runs `shortcut` on `model`.
    @discardableResult
    static func perform(_ shortcut: VideoShortcut, model: VideoStudioModel, screenModalIsUp: Bool = false) -> Outcome {
        guard passesGate(shortcut, model: model, screenModalIsUp: screenModalIsUp) else { return .done }
        switch shortcut {
        case .playPause: model.togglePlayback()
        case .stop: model.shuttle(.k)
        case .playBackward: model.shuttle(.j)
        case .playForward, .faster: model.shuttle(.l)
        case .backSecond: model.seek(to: model.currentTime - 1)
        case .forwardSecond: model.seek(to: model.currentTime + 1)
        case .backFrame: model.stepFrames(-1)
        case .forwardFrame: model.stepFrames(1)
        case .goToStart: model.goToStart()
        case .goToEnd: model.goToEnd()
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
        case .zoomIn: model.stepZoom(zoomsIn: true)
        case .zoomOut: model.stepZoom(zoomsIn: false)
        case .markIn: model.markIn()
        case .markOut: model.markOut()
        case .clearInOut: model.clearInOut()
        }
        return .done
    }
}
