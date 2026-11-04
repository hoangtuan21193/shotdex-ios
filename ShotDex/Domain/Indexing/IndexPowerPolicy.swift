import Foundation

/// When automatic indexing waits for power (FS-18.04 §3 AC-75): always in
/// Low Power Mode, and on a Mac running on its battery when Settings ›
/// Sources › Pause Indexing on Battery Power is on. A run the user starts by
/// hand still goes.
enum IndexPowerPolicy {
    enum Hold: Equatable, Sendable {
        case none
        case lowPower
        case battery
    }

    /// `onAdapter` is false only on battery; a desktop has none and is always on its adapter.
    static func hold(lowPower: Bool, onAdapter: Bool, pausesOnBattery: Bool) -> Hold {
        if lowPower { return .lowPower }
        if pausesOnBattery, !onAdapter { return .battery }
        return .none
    }

    /// What a change of hold does to indexing: stop an automatic run that
    /// is going, pick indexing up when the battery hold ends, or nothing. A
    /// run the user started goes on.
    enum Step: Equatable, Sendable { case none, cancel, resume }

    static func step(from previous: Hold, to next: Hold, isRunActive: Bool, isManualRun: Bool) -> Step {
        if previous == .none, next != .none, isRunActive, !isManualRun { return .cancel }
        if previous == .battery, next == .none, !isRunActive { return .resume }
        return .none
    }

    /// Pause Indexing on Battery Power, as stored: on by default on the Mac,
    /// where Settings shows it; the iPhone and iPad have no such switch.
    static func pausesOnBattery(_ defaults: UserDefaults = .standard) -> Bool {
        #if os(macOS)
        pausesOnBattery(defaults, isMac: true)
        #else
        pausesOnBattery(defaults, isMac: false)
        #endif
    }

    static func pausesOnBattery(_ defaults: UserDefaults, isMac: Bool) -> Bool {
        guard isMac else { return false }
        return defaults.object(forKey: SettingsKeys.pausesIndexingOnBattery) == nil
            ? true : defaults.bool(forKey: SettingsKeys.pausesIndexingOnBattery)
    }
}
