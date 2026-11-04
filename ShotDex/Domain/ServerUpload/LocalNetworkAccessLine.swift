import Foundation

/// Settings › Servers › Local Network Access (FS-18.04 §3 AC-78): what the
/// Bonjour browser's answer means for the user.
enum LocalNetworkAccessLine: Equatable {
    case checking
    case allowed
    case off

    /// `isSearching`: the first look is not over. `isDenied`: the browser was
    /// refused after a prompt closed. `refusedBeforePrompt`: refused with no
    /// prompt seen closing — the system asking now, or an answer given long
    /// ago; still refused once the look is over, it is the second: Off.
    static func from(isSearching: Bool, isDenied: Bool, refusedBeforePrompt: Bool) -> LocalNetworkAccessLine {
        if isDenied { return .off }
        if isSearching { return .checking }
        return refusedBeforePrompt ? .off : .allowed
    }

    var text: String {
        switch self {
        case .checking: String(localized: "Checking…", comment: "Local Network Access: the answer is not in yet")
        case .allowed: String(localized: "Allowed · ShotDex can find computers and NAS drives on this network",
                              comment: "Local Network Access: on")
        case .off: String(localized: "Off · ShotDex cannot find the computers and NAS drives near this Mac",
                          comment: "Local Network Access: off")
        }
    }

    /// System Settings › Privacy & Security › Local Network.
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
}
