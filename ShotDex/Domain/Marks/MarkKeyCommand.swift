import Foundation

/// What one key does to the photo (or photos) it lands on.
enum MarkKeyAction: Equatable, Sendable {
    case rate(Int)
    /// `nil` clears the flag (`U`).
    case flag(PhotoFlag?)
}

/// The rating and flag keys of FS-01.12 §6: `0` clears the stars, `1`–`5`
/// set them, `P` picks, `X` rejects, `U` clears the flag. One table, read by
/// the viewer, the selection and the culling pass, so a key cannot mean two
/// things on two screens.
///
/// They hang off hidden buttons that call the same function as the menu row
/// (SwiftUI cannot fire a shortcut inside a closed `Menu`), which is why this
/// is data and not a switch in each view.
enum MarkKeyCommand {
    struct Binding: Equatable, Sendable {
        let key: Character
        let action: MarkKeyAction
    }

    static let bindings: [Binding] = StarRating.range.map {
        Binding(key: Character(String($0)), action: .rate($0))
    } + [
        Binding(key: "p", action: .flag(.pick)),
        Binding(key: "x", action: .flag(.reject)),
        Binding(key: "u", action: .flag(nil)),
    ]

    /// Keys the viewer already answers (`F` favorite, `I` info). Delete and
    /// ⌘S are not characters and cannot collide.
    static let viewerKeys: Set<Character> = ["f", "i"]

    static func action(for key: Character) -> MarkKeyAction? {
        let lowered = Character(key.lowercased())
        return bindings.first { $0.key == lowered }?.action
    }
}

extension MarkKeyAction {
    /// The name the ⌘ shortcut overlay lists for the key.
    var shortcutTitle: String {
        switch self {
        case .rate(0): MarkCopy.noRating
        case .rate(let stars): MarkCopy.starsAccessibility(stars)
        case .flag(.pick): MarkCopy.pick
        case .flag(.reject): MarkCopy.reject
        case .flag(nil): MarkCopy.clearFlag
        }
    }
}
