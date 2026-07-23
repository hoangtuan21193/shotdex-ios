import Foundation
import Testing
@testable import ShotDex

/// Pure display/paused logic for the indexing network status line.
struct IndexNetworkStatusTests {

    @Test func cellularWithoutOptInIsPaused() {
        let status = IndexNetworkStatus(
            connection: .cellular,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            allowsNetwork: false
        )
        #expect(status.streamingPaused)
        #expect(status.displayLine == "Cellular · Paused — Wi-Fi needed")
    }

    @Test func cellularWithOptInIsNotPaused() {
        let status = IndexNetworkStatus(
            connection: .cellular,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            allowsNetwork: true
        )
        #expect(!status.streamingPaused)
        #expect(!status.displayLine.contains("Paused"))
    }

    @Test func wifiIsNeverPaused() {
        let status = IndexNetworkStatus(
            connection: .wifi,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            allowsNetwork: false
        )
        // Only a metered cellular path pauses; Wi-Fi never does.
        #expect(!status.streamingPaused)
        #expect(status.displayLine == "Wi-Fi")
    }

    @Test func wifiShowsSpeedAndTotalWhenStreaming() {
        let status = IndexNetworkStatus(
            connection: .wifi,
            bytesDownloaded: 2_000_000,
            bytesPerSecond: 1_000_000,
            allowsNetwork: true
        )
        #expect(!status.streamingPaused)
        // Connection name, then speed, then total — separated by " · ".
        let parts = status.displayLine.components(separatedBy: " · ")
        #expect(parts.count == 3)
        #expect(parts.first == "Wi-Fi")
    }
}

/// Half-open circuit breaker + iCloud read counters on the traffic monitor.
struct IndexTrafficMonitorTests {

    private func trip(_ monitor: IndexTrafficMonitor) {
        for _ in 0..<IndexTrafficMonitor.stallTripThreshold {
            monitor.recordNetworkStall()
        }
    }

    @Test func breakerTripsAtThreshold() {
        let monitor = IndexTrafficMonitor(cooldown: .seconds(60))
        for _ in 1..<IndexTrafficMonitor.stallTripThreshold {
            #expect(monitor.recordNetworkStall() == false)
        }
        #expect(monitor.recordNetworkStall() == true)
        #expect(monitor.isNetworkTripped)
        #expect(monitor.breakerCooldownRemaining != nil)
    }

    @Test func breakerHalfOpensAfterCooldown() async throws {
        let monitor = IndexTrafficMonitor(cooldown: .milliseconds(50))
        trip(monitor)
        #expect(monitor.isNetworkTripped)
        try await Task.sleep(for: .milliseconds(80))
        // Cooldown elapsed — reads may probe the network again.
        #expect(!monitor.isNetworkTripped)
        #expect(monitor.breakerCooldownRemaining == nil)
    }

    @Test func stalledProbeReTrips() async throws {
        let monitor = IndexTrafficMonitor(cooldown: .milliseconds(50))
        trip(monitor)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!monitor.isNetworkTripped)
        // The half-open probe stalled — re-trip for another cooldown.
        #expect(monitor.recordNetworkStall() == true)
        #expect(monitor.isNetworkTripped)
    }

    @Test func progressClosesBreakerFully() async throws {
        let monitor = IndexTrafficMonitor(cooldown: .milliseconds(50))
        trip(monitor)
        try await Task.sleep(for: .milliseconds(80))
        monitor.recordNetworkProgress()
        #expect(!monitor.isNetworkTripped)
        // Fully closed: the next stall starts a fresh streak, no re-trip.
        #expect(monitor.recordNetworkStall() == false)
        #expect(!monitor.isNetworkTripped)
    }

    @Test func lateStallDuringCooldownIsIgnored() {
        let monitor = IndexTrafficMonitor(cooldown: .seconds(60))
        trip(monitor)
        // Reads already in flight at trip time can stall late —
        // no state change, no second "tripped" signal.
        #expect(monitor.recordNetworkStall() == false)
        #expect(monitor.isNetworkTripped)
    }

    @Test func lateProgressDuringCooldownDoesNotCancelTheTrip() {
        let monitor = IndexTrafficMonitor(cooldown: .seconds(60))
        trip(monitor)
        // An in-flight read delivering its buffered bytes right after the
        // trip must not defeat the quiet period.
        monitor.recordNetworkProgress()
        #expect(monitor.isNetworkTripped)
    }

    @Test func nonConsecutiveStallsStillTrip() {
        // A wedged iCloud that leaks the odd few bytes: stalls with a couple
        // of successes interleaved. The old consecutive-streak breaker never
        // tripped here (each success reset it), leaving the run at 0 KB/s
        // indefinitely; the sliding window (≥10 of 12) must trip.
        let monitor = IndexTrafficMonitor(cooldown: .seconds(60))
        var tripped = false
        for index in 0..<IndexTrafficMonitor.stallTripThreshold {
            if index % 8 == 0 {
                monitor.recordNetworkProgress()
            } else if monitor.recordNetworkStall() {
                tripped = true
            }
        }
        #expect(tripped)
        #expect(monitor.isNetworkTripped)
    }

    @Test func mostlyHealthyLinkNeverTrips() {
        // Half the reads stall (heavy congestion, but data flows): well under
        // the 20-of-24 ratio — the breaker must stay closed.
        let monitor = IndexTrafficMonitor(cooldown: .seconds(60))
        for _ in 0..<(IndexTrafficMonitor.stallTripThreshold * 3) {
            #expect(monitor.recordNetworkStall() == false)
            monitor.recordNetworkProgress()
        }
        #expect(!monitor.isNetworkTripped)
    }

    @Test func halfOpenAllowsExactlyOneProbe() async throws {
        let monitor = IndexTrafficMonitor(cooldown: .milliseconds(50))
        #expect(monitor.shouldSkipNetworkRead() == false)   // closed — reads flow
        trip(monitor)
        #expect(monitor.shouldSkipNetworkRead())            // cooling — everyone skips
        try await Task.sleep(for: .milliseconds(80))
        #expect(monitor.shouldSkipNetworkRead() == false)   // first caller claims the probe
        #expect(monitor.shouldSkipNetworkRead())            // the rest stay blocked
        monitor.recordNetworkStall()                        // probe stalled — re-trip
        #expect(monitor.isNetworkTripped)
        #expect(monitor.shouldSkipNetworkRead())
    }

    @Test func probeSuccessUnblocksAllReads() async throws {
        let monitor = IndexTrafficMonitor(cooldown: .milliseconds(50))
        trip(monitor)
        try await Task.sleep(for: .milliseconds(80))
        #expect(monitor.shouldSkipNetworkRead() == false)   // probe out
        monitor.recordNetworkProgress()                     // probe delivered bytes
        #expect(monitor.shouldSkipNetworkRead() == false)   // breaker closed — all flow
        #expect(monitor.shouldSkipNetworkRead() == false)
    }

    @Test func stallStartsRestWindow() async throws {
        let monitor = IndexTrafficMonitor(restDuration: .milliseconds(50))
        #expect(monitor.networkRestRemaining == nil)
        monitor.recordNetworkStall()
        #expect(monitor.networkRestRemaining != nil)
        try await Task.sleep(for: .milliseconds(80))
        // Breather expired on its own — reads flow again.
        #expect(monitor.networkRestRemaining == nil)
    }

    @Test func resetClearsRestWindow() {
        let monitor = IndexTrafficMonitor(restDuration: .seconds(60))
        monitor.recordNetworkStall()
        #expect(monitor.networkRestRemaining != nil)
        monitor.reset()
        #expect(monitor.networkRestRemaining == nil)
    }

    @Test func countersTrackReadsAndReset() {
        let monitor = IndexTrafficMonitor()
        monitor.beginNetworkRead()
        monitor.beginNetworkRead()
        #expect(monitor.networkReadsStarted == 2)
        #expect(monitor.networkReadsInFlight == 2)
        monitor.endNetworkRead()
        #expect(monitor.networkReadsStarted == 2)
        #expect(monitor.networkReadsInFlight == 1)
        monitor.recordNetworkStall()
        #expect(monitor.stallCount == 1)
        monitor.reset()
        #expect(monitor.networkReadsStarted == 0)
        #expect(monitor.networkReadsInFlight == 0)
        #expect(monitor.stallCount == 0)
        #expect(!monitor.isNetworkTripped)
    }
}

/// Display lines of the indexing diagnostics readout.
struct IndexDiagnosticsTests {

    private func make(
        started: Int = 132, inFlight: Int = 4, stalls: Int = 0,
        cooldown: Duration? = nil, lowPowerMode: Bool = false
    ) -> IndexDiagnostics {
        IndexDiagnostics(
            thermalState: .fair,
            readConcurrency: 6,
            lowPowerMode: lowPowerMode,
            networkReadsStarted: started,
            networkReadsInFlight: inFlight,
            stallCount: stalls,
            breakerCooldownRemaining: cooldown
        )
    }

    @Test func thermalLineShowsStateAndConcurrency() {
        #expect(make().thermalLine == "Thermal: Fair · 6 readers")
    }

    @Test func thermalLineAppendsLowPower() {
        #expect(make(lowPowerMode: true).thermalLine == "Thermal: Fair · 6 readers · Low Power")
    }

    @Test func iCloudLineShowsCounts() {
        #expect(make().iCloudLine == "iCloud: 4 in flight · 132 requested")
    }

    @Test func iCloudLineAppendsStallsWhenPresent() {
        #expect(make(stalls: 12).iCloudLine == "iCloud: 4 in flight · 132 requested · 12 stalls")
    }

    @Test func iCloudLineShowsBreakerCooldown() {
        #expect(make(cooldown: .seconds(42)).iCloudLine == "iCloud paused · retry in 42s")
    }
}
