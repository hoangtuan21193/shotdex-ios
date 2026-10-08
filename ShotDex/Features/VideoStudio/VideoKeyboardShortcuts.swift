import SwiftUI
import UIKit

/// The Video Studio's keyboard (FS-12.17b §3): every key comes from
/// `VideoShortcut` — one list makes the keys and every list of them.
///
/// - iPhone and the Duo: a layer of zero-size buttons, one per shortcut —
///   a shortcut on a visible control only fires while the control is on
///   screen, and most of these have no control.
/// - iPad: the menu bar's commands (`VideoStudioCommands`), so the system's
///   ⌘ list shows them in three groups — Playback · Edit · View — and no
///   key is listed twice. Undo and Redo stay in the layer there: the
///   system's Edit menu owns ⌘Z for every text field in the app.

extension VideoShortcut.Key {
    var keyEquivalent: KeyEquivalent {
        switch input {
        case .character(let character): KeyEquivalent(character)
        case .space: .space
        case .escape: .escape
        case .delete: .delete
        case .returnKey: .return
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .home: .home
        case .end: .end
        }
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}

/// What a shortcut does, and whether it can right now — handed to the
/// layer and, on the iPad, to the menu bar through a focused value.
@MainActor
struct VideoStudioKeyboardActions {
    let perform: (VideoShortcut) -> Void
    let isEnabled: (VideoShortcut) -> Bool
}

/// The menu bar's way to the open studio: **one object per screen**, its
/// closures refreshed on every render. A focused value that changed with
/// every render — a struct of closures — had the scene re-render forever
/// and hung the iPad as the studio opened.
@MainActor
final class VideoStudioKeyboardTarget {
    var perform: (VideoShortcut) -> Void = { _ in }
    var isEnabled: (VideoShortcut) -> Bool = { _ in false }
}

/// The zero-size buttons that carry the keys (iPhone, Duo; Undo and Redo
/// on the iPad).
struct VideoKeyboardShortcutLayer: View {
    let shortcuts: [VideoShortcut]
    let actions: VideoStudioKeyboardActions

    var body: some View {
        ZStack {
            ForEach(shortcuts) { shortcut in
                if let key = shortcut.key {
                    Button(VideoStudioCopy.shortcutName(shortcut)) { actions.perform(shortcut) }
                        .keyboardShortcut(key.keyEquivalent, modifiers: key.eventModifiers)
                        .disabled(!actions.isEnabled(shortcut))
                }
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// The Video Studio's keys in the iPad's menu bar, while the studio is the
/// scene's (`focusedSceneValue`): Playback a menu of its own, the editing
/// keys after the system's Edit items, the view keys in View.
struct VideoStudioCommands: Commands {
    @FocusedValue(\.videoStudioKeyboard) private var keyboard: VideoStudioKeyboardTarget?

    var body: some Commands {
        CommandMenu(Text(verbatim: VideoStudioCopy.shortcutGroupName(.playback))) {
            buttons(.playback)
        }
        CommandGroup(after: .pasteboard) {
            buttons(.edit, excluding: [.undo, .redo])
        }
        CommandGroup(after: .toolbar) {
            buttons(.view)
        }
    }

    @ViewBuilder
    private func buttons(_ group: VideoShortcut.Group, excluding: Set<VideoShortcut> = []) -> some View {
        if let keyboard {
            ForEach(VideoShortcut.built.filter { $0.group == group && !excluding.contains($0) }) { shortcut in
                if let key = shortcut.key {
                    Button(VideoStudioCopy.shortcutName(shortcut)) { keyboard.perform(shortcut) }
                        .keyboardShortcut(key.keyEquivalent, modifiers: key.eventModifiers)
                        .disabled(!keyboard.isEnabled(shortcut))
                }
            }
        }
    }
}

struct VideoStudioKeyboardKey: FocusedValueKey {
    typealias Value = VideoStudioKeyboardTarget
}

extension FocusedValues {
    var videoStudioKeyboard: VideoStudioKeyboardTarget? {
        get { self[VideoStudioKeyboardKey.self] }
        set { self[VideoStudioKeyboardKey.self] = newValue }
    }
}

extension VideoStudioScreen {
    /// The studio's keys for a window of `windowClass`.
    func keyboardShortcuts(_ model: VideoStudioModel) -> some View {
        let actions = keyboardActions(model)
        let isIPad = currentWindowClass == .iPadLandscape || currentWindowClass == .iPadPortrait
        keyboardTarget.perform = actions.perform
        keyboardTarget.isEnabled = actions.isEnabled
        return VideoKeyboardShortcutLayer(
            shortcuts: isIPad ? [.undo, .redo] : VideoShortcut.built,
            actions: actions
        )
        .focusedSceneValue(\.videoStudioKeyboard, isIPad ? keyboardTarget : nil)
    }

    func keyboardActions(_ model: VideoStudioModel) -> VideoStudioKeyboardActions {
        VideoStudioKeyboardActions(
            perform: { performShortcut($0, model: model) },
            isEnabled: { shortcutIsEnabled($0, model: model) }
        )
    }

    func shortcutIsEnabled(_ shortcut: VideoShortcut, model: VideoStudioModel) -> Bool {
        VideoKeyboardRouter.isEnabled(shortcut, model: model, screenModalIsUp: presentsModal)
    }

    func performShortcut(_ shortcut: VideoShortcut, model: VideoStudioModel) {
        switch VideoKeyboardRouter.perform(shortcut, model: model, screenModalIsUp: presentsModal) {
        case .done: break
        case .openExport: openExport(model)
        }
    }
}

/// Whether anything in the app is being typed in (FS-12.17b §3): a text
/// field or a text view began editing and has not ended. SwiftUI's
/// `TextField` and `TextEditor` are UIKit's underneath, so their
/// notifications cover every field the studio has, panels and sheets
/// alike, without each one reporting its focus.
@MainActor
final class VideoTextInputMonitor {
    private var editing: Set<ObjectIdentifier> = []
    private var observers: [NSObjectProtocol] = []

    /// Starts reporting to `onChange`; once is enough.
    func start(_ onChange: @escaping @MainActor (Bool) -> Void) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let pairs: [(Notification.Name, Bool)] = [
            (UITextField.textDidBeginEditingNotification, true),
            (UITextField.textDidEndEditingNotification, false),
            (UITextView.textDidBeginEditingNotification, true),
            (UITextView.textDidEndEditingNotification, false),
        ]
        for (name, begins) in pairs {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let object = note.object as AnyObject? else { return }
                let id = ObjectIdentifier(object)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if begins { self.editing.insert(id) } else { self.editing.remove(id) }
                    onChange(!self.editing.isEmpty)
                }
            })
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        editing.removeAll()
    }
}

/// Counts a sheet or alert a panel opens over the studio while it is up
/// (FS-12.17b §3): the keys are silent under it.
struct VideoStudioModalPresence: ViewModifier {
    let model: VideoStudioModel?
    let isPresented: Bool
    /// Whether this one is in the model's count now.
    @State private var isCounted = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in count(presented) }
            .onDisappear { count(false) }
    }

    private func count(_ presented: Bool) {
        guard let model, presented != isCounted else { return }
        isCounted = presented
        model.nestedModalCount = max(0, model.nestedModalCount + (presented ? 1 : -1))
    }
}

extension View {
    /// The keys go quiet while `isPresented` (FS-12.17b §3).
    func silencesVideoStudioKeys(_ model: VideoStudioModel?, while isPresented: Bool) -> some View {
        modifier(VideoStudioModalPresence(model: model, isPresented: isPresented))
    }
}
