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
            isNetworkAllowed: false
        )
        #expect(status.isStreamingPaused)
        #expect(status.displayLine == "Paused — waiting for Wi-Fi")
    }

    @Test func cellularWithOptInIsNotPaused() {
        let status = IndexNetworkStatus(
            connection: .cellular,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            isNetworkAllowed: true
        )
        #expect(!status.isStreamingPaused)
        #expect(!status.displayLine.contains("Paused"))
    }

    @Test func wifiIsNeverPaused() {
        let status = IndexNetworkStatus(
            connection: .wifi,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            isNetworkAllowed: false
        )
        // Only a metered cellular path pauses; Wi-Fi never does.
        #expect(!status.isStreamingPaused)
        // Nothing downloaded yet — said in words, not as a bare "0 KB".
        #expect(status.displayLine == "Wi-Fi · nothing downloaded yet")
    }

    @Test func wifiShowsSpeedAndTotalWhenStreaming() {
        let status = IndexNetworkStatus(
            connection: .wifi,
            bytesDownloaded: 2_000_000,
            bytesPerSecond: 1_000_000,
            isNetworkAllowed: true
        )
        #expect(!status.isStreamingPaused)
        // Connection name, then speed, then a labelled total — " · " apart.
        let parts = status.displayLine.components(separatedBy: " · ")
        #expect(parts.count == 3)
        #expect(parts.first == "Wi-Fi")
        #expect(parts.last?.hasSuffix("downloaded from iCloud") == true)
    }

    @Test func detailedLineKeepsZerosForTheDimOverlay() {
        let status = IndexNetworkStatus(
            connection: .wifi,
            bytesDownloaded: 0,
            bytesPerSecond: nil,
            isNetworkAllowed: true
        )
        // The dim overlay wants a stable readout, so zeros stay numeric here
        // even though `displayLine` spells them out.
        let parts = status.detailedLine.components(separatedBy: " · ")
        #expect(parts.count == 3)
        #expect(parts[1].hasSuffix("/s"))
        #expect(parts[2].hasSuffix("downloaded from iCloud"))
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
        cooldown: Duration? = nil, isLowPowerMode: Bool = false,
        thermalState: ProcessInfo.ThermalState = .fair
    ) -> IndexDiagnostics {
        IndexDiagnostics(
            thermalState: thermalState,
            readConcurrency: 6,
            isLowPowerMode: isLowPowerMode,
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
        #expect(make(isLowPowerMode: true).thermalLine == "Thermal: Fair · 6 readers · Low Power")
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

    @Test func healthyRunHasNoAdvisories() {
        // Nominal and fair are the normal case — nothing to explain, so the
        // UI shows no warning line at all.
        #expect(make().advisories.isEmpty)
        #expect(make(thermalState: .nominal).advisories.isEmpty)
        // Stalls alone are internal detail; only the tripped breaker is news.
        #expect(make(stalls: 12).advisories.isEmpty)
    }

    @Test func advisoriesExplainWhatSlowsTheRun() {
        #expect(make(cooldown: .seconds(42)).advisories == [
            "iCloud isn't responding — trying again in 42s"
        ])
        #expect(make(thermalState: .serious).advisories == [
            "Your iPhone is warm — indexing slowed down to cool it"
        ])
        #expect(make(thermalState: .critical).advisories == [
            "Indexing paused until your iPhone cools down"
        ])
        #expect(make(isLowPowerMode: true).advisories == [
            "Low Power Mode is slowing indexing down"
        ])
    }

    @Test func advisoriesStackWorstFirst() {
        let lines = make(
            cooldown: .seconds(30), isLowPowerMode: true, thermalState: .serious
        ).advisories
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("iCloud isn't responding"))
        #expect(lines[1].hasPrefix("Your iPhone is warm"))
        #expect(lines[2].hasPrefix("Low Power Mode"))
    }
}

/// Plain-language speed / time-left lines.
struct IndexThroughputTests {

    @Test func rateTextGroupsThousands() {
        #expect(IndexThroughput(photosPerMinute: 1548.4, remaining: nil).rateText
            == "1,548 photos and videos per minute")
    }

    @Test func remainingTextReadsAsAnEstimate() {
        func text(_ seconds: Int) -> String? {
            IndexThroughput(photosPerMinute: 100, remaining: .seconds(seconds)).remainingText
        }
        #expect(text(30) == "Less than a minute left")
        #expect(text(45 * 60) == "About 45 min left")
        #expect(text(2 * 3600) == "About 2 hours left")
        #expect(text(3600) == "About 1 hour left")
        #expect(text(2 * 3600 + 15 * 60) == "About 2 hr 15 min left")
    }

    @Test func summaryLinePutsTimeLeftFirst() {
        let throughput = IndexThroughput(photosPerMinute: 96, remaining: .seconds(600))
        #expect(throughput.summaryLine == "About 10 min left · 96 photos and videos per minute")
        // No estimate yet — the rate stands alone rather than showing a gap.
        #expect(IndexThroughput(photosPerMinute: 96, remaining: nil).summaryLine
            == "96 photos and videos per minute")
    }
}
