import Foundation

/// What a card import does when the app leaves the screen (FS-20 §7,
/// AC-26): on iOS 26 a run the user started asks the system to carry on —
/// progress shows in the system's own UI; before 26, or when the system
/// said no, it stops cleanly like Stop, with Import Remaining waiting.
enum IngestBackgroundPolicy {
    enum Action: Equatable { case keepRunning, stop }

    static func onBackground(isRunning: Bool, hasContinuedTask: Bool) -> Action {
        guard isRunning else { return .keepRunning }
        return hasContinuedTask ? .keepRunning : .stop
    }
}
