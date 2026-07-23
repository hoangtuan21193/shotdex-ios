import Foundation
import UIKit
import os

/// Watches the device power state so index runs can react to Low Power Mode and
/// charging: LPM stops automatic indexing (the user may still start it by hand),
/// and plugging in a charger while in LPM resumes it.
///
/// Mirrors `NetworkStatusService`: plain `Sendable`, lock-guarded state, a single
/// observer handler, notification observers torn down in `deinit`.
final class PowerStatusService: Sendable {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "power")

    private let lowPower = OSAllocatedUnfairLock(initialState: false)
    private let charging = OSAllocatedUnfairLock(initialState: false)
    /// Optional observer (the indexing controller) notified on every power
    /// change with `(isLowPowerMode, isCharging)`.
    private let observer = OSAllocatedUnfairLock<
        (@Sendable (Bool, Bool) -> Void)?
    >(initialState: nil)
    private let tokens = OSAllocatedUnfairLock<[NSObjectProtocol]>(initialState: [])

    init() {
        // Battery state stays `.unknown` until monitoring is enabled.
        UIDevice.current.isBatteryMonitoringEnabled = true
        lowPower.withLock { $0 = ProcessInfo.processInfo.isLowPowerModeEnabled }
        charging.withLock { $0 = Self.isChargingNow() }

        let center = NotificationCenter.default
        let powerToken = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        let batteryToken = center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        tokens.withLock { $0 = [powerToken, batteryToken] }
    }

    /// Registers the single power-change observer (the indexing controller).
    /// Replaces any previous handler.
    func setPowerChangeHandler(_ handler: (@Sendable (Bool, Bool) -> Void)?) {
        observer.withLock { $0 = handler }
    }

    /// True when the system is in Low Power Mode.
    var isLowPowerMode: Bool {
        lowPower.withLock { $0 }
    }

    /// True when the device is charging or fully charged on external power.
    var isCharging: Bool {
        charging.withLock { $0 }
    }

    private func refresh() {
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        let chg = Self.isChargingNow()
        lowPower.withLock { $0 = lpm }
        charging.withLock { $0 = chg }
        Self.logger.debug("power update: lowPower \(lpm), charging \(chg)")
        observer.withLock { $0 }?(lpm, chg)
    }

    private static func isChargingNow() -> Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: true
        default: false
        }
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens.withLock({ $0 }) {
            center.removeObserver(token)
        }
    }
}
