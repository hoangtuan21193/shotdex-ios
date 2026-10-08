import Foundation

/// The Video Studio's 28 keyboard shortcuts (FS-12.17b §3): **one** list that
/// makes both the keys and every list of them, so a list never shows a key
/// that does not work. Names as the boards write them (F6_IL_Shortcuts);
/// the iPad shows them in three groups, the phone and the Duo fold them
/// into twelve rows (§4).
enum VideoShortcut: String, CaseIterable, Identifiable, Sendable {
    // Playback (11)
    case playPause, stop, playBackward, playForward, faster
    case backSecond, forwardSecond, backFrame, forwardFrame, goToStart, goToEnd
    // Edit (10)
    case split, markIn, markOut, clearInOut, trimStart, trimEnd, delete, addMarker, undo, redo
    // View (7)
    case zoomIn, zoomOut, fitTimeline, selectAll, deselect, beforeAfter, export

    var id: String { rawValue }

    enum Group: CaseIterable, Sendable {
        case playback, edit, view
    }

    /// A key and its modifiers — the Domain's own type, not SwiftUI's.
    struct Key: Equatable, Hashable, Sendable {
        enum Input: Equatable, Hashable, Sendable {
            case character(Character)
            case space, escape, delete, returnKey, leftArrow, rightArrow, home, end
        }

        enum Modifier: Equatable, Hashable, Sendable, Comparable {
            case control, option, shift, command
        }

        var input: Input
        var modifiers: Set<Modifier> = []

        /// A key with no modifier answers only while nobody is typing
        /// (§3): Space, J, K, L, I, O, M, \, ⌫.
        var isBare: Bool { modifiers.isEmpty }
    }

    var group: Group {
        switch self {
        case .playPause, .stop, .playBackward, .playForward, .faster,
             .backSecond, .forwardSecond, .backFrame, .forwardFrame, .goToStart, .goToEnd:
            .playback
        case .split, .markIn, .markOut, .clearInOut, .trimStart, .trimEnd, .delete, .addMarker, .undo, .redo:
            .edit
        case .zoomIn, .zoomOut, .fitTimeline, .selectAll, .deselect, .beforeAfter, .export:
            .view
        }
    }

    /// The key that runs it. Faster has none of its own: it is L pressed
    /// again while playing forward — listed, never registered twice.
    var key: Key? {
        switch self {
        case .playPause: Key(input: .space)
        case .stop: Key(input: .character("k"))
        case .playBackward: Key(input: .character("j"))
        case .playForward: Key(input: .character("l"))
        case .faster: nil
        case .backSecond: Key(input: .leftArrow)
        case .forwardSecond: Key(input: .rightArrow)
        case .backFrame: Key(input: .leftArrow, modifiers: [.shift])
        case .forwardFrame: Key(input: .rightArrow, modifiers: [.shift])
        case .goToStart: Key(input: .home)
        case .goToEnd: Key(input: .end)
        case .split: Key(input: .character("b"), modifiers: [.command])
        case .markIn: Key(input: .character("i"))
        case .markOut: Key(input: .character("o"))
        case .clearInOut: Key(input: .character("x"), modifiers: [.option])
        case .trimStart: Key(input: .character("["), modifiers: [.option])
        case .trimEnd: Key(input: .character("]"), modifiers: [.option])
        case .delete: Key(input: .delete)
        case .addMarker: Key(input: .character("m"))
        case .undo: Key(input: .character("z"), modifiers: [.command])
        case .redo: Key(input: .character("z"), modifiers: [.command, .shift])
        case .zoomIn: Key(input: .character("="), modifiers: [.command])
        case .zoomOut: Key(input: .character("-"), modifiers: [.command])
        case .fitTimeline: Key(input: .character("z"), modifiers: [.shift])
        case .selectAll: Key(input: .character("a"), modifiers: [.command])
        case .deselect: Key(input: .escape)
        case .beforeAfter: Key(input: .character("\\"))
        case .export: Key(input: .character("e"), modifiers: [.command])
        }
    }

    /// The keycaps a list draws: "⌘B", "⇧←", "L L", "Space".
    var keyLabel: String {
        guard let key else { return "L L" }
        return Self.label(key)
    }

    static func label(_ key: Key) -> String {
        let modifiers = key.modifiers.sorted().map { modifier -> String in
            switch modifier {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }.joined()
        let input: String = switch key.input {
        case .character("="): "+"
        case .character("-"): "−"
        case .character(let character): String(character).uppercased()
        case .space: "Space"
        case .escape: "Esc"
        case .delete: "⌫"
        case .returnKey: "↩"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .home: "Home"
        case .end: "End"
        }
        return modifiers + input
    }

    /// The shortcuts that run, in the list's order — all 28 since the
    /// In–Out keys landed (plan vs-precise-trim-input task 27).
    static var built: [VideoShortcut] { allCases }

    /// The shortcuts of `group`, in the list's order.
    static func shortcuts(in group: Group) -> [VideoShortcut] {
        allCases.filter { $0.group == group }
    }

    /// The twelve rows of the phone's and the Duo's card (§4, boards
    /// F6_P_Keyboard, F6_DI_Keyboard, F6_DC_Keyboard): related shortcuts
    /// folded into one row, in the boards' order.
    static let compactRows: [[VideoShortcut]] = [
        [.playPause],
        [.playBackward, .stop, .playForward],
        [.backFrame, .forwardFrame],
        [.split],
        [.markIn, .markOut],
        [.trimStart, .trimEnd],
        [.delete],
        [.addMarker],
        [.undo, .redo],
        [.zoomIn, .zoomOut],
        [.deselect],
        [.export],
    ]
}
