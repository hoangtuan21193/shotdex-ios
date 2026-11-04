import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-75: when automatic indexing waits for power.
@Suite struct PowerPolicyTests {
    /// On battery with the switch on: held; plugged back in: free again.
    @Test func batteryPausesIndex() {
        #expect(IndexPowerPolicy.hold(lowPower: false, onAdapter: false, pausesOnBattery: true) == .battery)
        #expect(IndexPowerPolicy.hold(lowPower: false, onAdapter: true, pausesOnBattery: true) == .none)
        // The switch off: battery does not hold.
        #expect(IndexPowerPolicy.hold(lowPower: false, onAdapter: false, pausesOnBattery: false) == .none)
        // Low Power Mode always holds, adapter or not.
        #expect(IndexPowerPolicy.hold(lowPower: true, onAdapter: true, pausesOnBattery: false) == .lowPower)
    }

    /// The row says why the index waits and what is left.
    @Test func pausedLine() {
        let state = IndexStatusLine.State.pausedOnBattery(waiting: 12_400)
        #expect(IndexStatusLine.title(state, counts: .init(photos: 0, videos: 0)) == "Paused on battery · \(12_400.formatted(.number)) waiting")
        #expect(IndexStatusLine.detail(state, counts: .init(photos: 0, videos: 0)) == "Indexing goes on when this Mac is plugged in, or turn off Pause Indexing on Battery Power.")
        #expect(IndexStatusLine.fraction(state) == nil)
    }

    /// Unplugging stops an automatic run, never one the user started;
    /// plugging back in picks indexing up; Low Power Mode ending does not.
    @Test func transitions() {
        #expect(IndexPowerPolicy.step(from: .none, to: .battery, isRunActive: true, isManualRun: false) == .cancel)
        #expect(IndexPowerPolicy.step(from: .none, to: .battery, isRunActive: true, isManualRun: true) == .none)
        #expect(IndexPowerPolicy.step(from: .battery, to: .none, isRunActive: false, isManualRun: false) == .resume)
        #expect(IndexPowerPolicy.step(from: .lowPower, to: .none, isRunActive: false, isManualRun: false) == .none)
        #expect(IndexPowerPolicy.step(from: .none, to: .none, isRunActive: true, isManualRun: false) == .none)
    }

    /// On the Mac the switch is on until turned off.
    @Test func macDefaultsToPausing() throws {
        let suite = "PowerPolicyTests-mac-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(IndexPowerPolicy.pausesOnBattery(defaults, isMac: true))
        defaults.set(false, forKey: SettingsKeys.pausesIndexingOnBattery)
        #expect(!IndexPowerPolicy.pausesOnBattery(defaults, isMac: true))
    }

    /// The iPhone and iPad have no such switch: battery never holds there.
    @Test func phonesNeverPauseOnBattery() throws {
        let suite = "PowerPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SettingsKeys.pausesIndexingOnBattery)
        #expect(IndexPowerPolicy.pausesOnBattery(defaults) == false)
    }
}
