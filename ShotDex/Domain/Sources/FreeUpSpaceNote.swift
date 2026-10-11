import Foundation

/// The line Free Up Space adds when the photos it deletes from Photos stay
/// in ShotDex through a server source (FS-19.03 §8).
enum FreeUpSpaceNote {
    static func line(keepingSources names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and))
        return String(localized: "They stay in ShotDex from \(list).",
                      comment: "Free Up Space confirmation: the deleted photos remain in the library through these server sources")
    }

    /// The confirmation's message with the line after it, when there is one.
    static func message(_ base: String, keepingSources names: [String]) -> String {
        line(keepingSources: names).map { base + "\n\n" + $0 } ?? base
    }
}
