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
    /// Return = ✓ (FS-12.17b §3), on every device — it is in no menu.
    var pressReturn: () -> Void = {}
    var returnIsEnabled: () -> Bool = { false }
}

/// The menu bar's way to the open studio: **one object per screen**, its
/// closure refreshed on every render. A focused value that changed with
/// every render — a struct of closures — had the scene re-render forever
/// and hung the iPad as the studio opened.
@MainActor
final class VideoStudioKeyboardTarget {
    var perform: (VideoShortcut) -> Void = { _ in }
}

/// What the menu bar reads (FS-12.17b §4): the studio's target and which
/// keys can act now. Equal while neither changes, so the menu is rebuilt
/// when a key is greyed out or back — Esc once a clip is selected — and
/// not on every frame of playback.
struct VideoStudioKeyboardState: Equatable {
    let target: VideoStudioKeyboardTarget
    let enabled: Set<VideoShortcut>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target === rhs.target && lhs.enabled == rhs.enabled
    }
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
    @FocusedValue(\.videoStudioKeyboard) private var keyboard: VideoStudioKeyboardState?

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
                    Button(VideoStudioCopy.shortcutName(shortcut)) { keyboard.target.perform(shortcut) }
                        .keyboardShortcut(key.keyEquivalent, modifiers: key.eventModifiers)
                        .disabled(!keyboard.enabled.contains(shortcut))
                }
            }
        }
    }
}

struct VideoStudioKeyboardKey: FocusedValueKey {
    typealias Value = VideoStudioKeyboardState
}

extension FocusedValues {
    var videoStudioKeyboard: VideoStudioKeyboardState? {
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
        let state = isIPad
            ? VideoStudioKeyboardState(target: keyboardTarget, enabled: Set(VideoShortcut.allCases.filter(actions.isEnabled)))
            : nil
        // Keys the system keeps for itself — arrows, Return, Esc, Home,
        // End, ⌫ — go through a UIKit responder that asks for priority;
        // SwiftUI's shortcuts never see them (FS-12.17b §3).
        let layerKeys = (isIPad ? [.undo, .redo] : VideoShortcut.built)
            .filter { !VideoSystemKeyResponder.handles($0) }
        return VideoKeyboardShortcutLayer(shortcuts: layerKeys, actions: actions)
            .background {
                VideoSystemKeyResponder(actions: actions, isTyping: model.isTypingText)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .focusedSceneValue(\.videoStudioKeyboard, state)
    }

    func keyboardActions(_ model: VideoStudioModel) -> VideoStudioKeyboardActions {
        VideoStudioKeyboardActions(
            perform: { performShortcut($0, model: model) },
            isEnabled: { shortcutIsEnabled($0, model: model) },
            pressReturn: { VideoKeyboardRouter.pressReturn(model: model, screenModalIsUp: presentsModal) },
            returnIsEnabled: { VideoKeyboardRouter.returnIsEnabled(model: model, screenModalIsUp: presentsModal) }
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

/// The keys iOS keeps for itself — ←/→, Return, Esc, Home, End, ⌫ — as
/// UIKit key commands that ask for priority over the system's behaviour
/// (focus moves, default and cancel actions). Registered by SwiftUI,
/// ← never arrived: measured 2026-10-08 on the iPad, ⇧← stepped and ←
/// did not; through this view ← moves the playhead a second. (Esc,
/// Return, Home and End sent by XCUITest never reach the app at all —
/// no `pressesBegan` — so those four are proven by unit tests and on a
/// device, not in the simulator.)
///
/// The responder is a hidden view that holds first responder while no
/// field is being typed in; a field takes it back by beginning to edit,
/// and the view reclaims it when editing ends. On the iPad the menu bar
/// still lists these keys (the system's ⌘ list); this view acts on them
/// first.
struct VideoSystemKeyResponder: UIViewRepresentable {
    let actions: VideoStudioKeyboardActions
    let isTyping: Bool

    /// Whether `shortcut`'s key is one the system would otherwise take.
    static func handles(_ shortcut: VideoShortcut) -> Bool {
        guard let input = shortcut.key?.input else { return false }
        switch input {
        case .leftArrow, .rightArrow, .escape, .returnKey, .home, .end, .delete: return true
        case .character, .space: return false
        }
    }

    static let shortcuts = VideoShortcut.allCases.filter(handles)

    func makeUIView(context: Context) -> KeyView {
        let view = KeyView()
        view.actions = actions
        return view
    }

    func updateUIView(_ view: KeyView, context: Context) {
        view.actions = actions
        view.isTyping = isTyping
        view.claimIfFree()
    }

    final class KeyView: UIView {
        var actions: VideoStudioKeyboardActions?
        var isTyping = false

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            claimIfFree()
        }

        func claimIfFree() {
            guard window != nil, !isTyping, !isFirstResponder else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, !self.isTyping, !self.isFirstResponder else { return }
                self.becomeFirstResponder()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            var commands = VideoSystemKeyResponder.shortcuts.compactMap { shortcut -> UIKeyCommand? in
                guard let key = shortcut.key else { return nil }
                let command = UIKeyCommand(
                    input: Self.input(key.input), modifierFlags: Self.flags(key.modifiers),
                    action: #selector(runShortcut(_:))
                )
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
            let confirm = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(runReturn(_:)))
            confirm.wantsPriorityOverSystemBehavior = true
            commands.append(confirm)
            return commands
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(runReturn(_:)) {
                return actions?.returnIsEnabled() ?? false
            }
            if action == #selector(runShortcut(_:)) {
                guard let command = sender as? UIKeyCommand, let shortcut = shortcut(for: command) else { return false }
                return actions?.isEnabled(shortcut) ?? false
            }
            return super.canPerformAction(action, withSender: sender)
        }

        @objc private func runShortcut(_ command: UIKeyCommand) {
            guard let shortcut = shortcut(for: command) else { return }
            actions?.perform(shortcut)
        }

        @objc private func runReturn(_ command: UIKeyCommand) {
            actions?.pressReturn()
        }

        private func shortcut(for command: UIKeyCommand) -> VideoShortcut? {
            VideoSystemKeyResponder.shortcuts.first { shortcut in
                guard let key = shortcut.key else { return false }
                return Self.input(key.input) == command.input
                    && Self.flags(key.modifiers) == command.modifierFlags.intersection([.shift, .command, .alternate, .control])
            }
        }

        static func input(_ input: VideoShortcut.Key.Input) -> String {
            switch input {
            case .character(let character): String(character)
            case .space: " "
            case .escape: UIKeyCommand.inputEscape
            case .delete: "\u{8}"
            case .returnKey: "\r"
            case .leftArrow: UIKeyCommand.inputLeftArrow
            case .rightArrow: UIKeyCommand.inputRightArrow
            case .home: UIKeyCommand.inputHome
            case .end: UIKeyCommand.inputEnd
            }
        }

        static func flags(_ modifiers: Set<VideoShortcut.Key.Modifier>) -> UIKeyModifierFlags {
            var flags: UIKeyModifierFlags = []
            if modifiers.contains(.shift) { flags.insert(.shift) }
            if modifiers.contains(.command) { flags.insert(.command) }
            if modifiers.contains(.option) { flags.insert(.alternate) }
            if modifiers.contains(.control) { flags.insert(.control) }
            return flags
        }
    }
}
