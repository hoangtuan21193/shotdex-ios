import Foundation
import os

/// Counts bytes streamed from iCloud during an index run. `ExifReader`
/// reports every received chunk; the indexing UI polls the total once a
/// second to derive a download speed.
final class IndexTrafficMonitor: Sendable {
    /// Central log stream for iCloud-read health during an index run: every
    /// stall, breaker trip/close, and the periodic health snapshot (logged by
    /// `LibraryModel`'s sampler) share this category, so
    /// `log stream --predicate 'category == "index-health"'` tells the whole
    /// story of a degrading run in one place.
    static let healthLogger = Logger(subsystem: "com.hoangtuan.shotdex", category: "index-health")

    private let bytes = OSAllocatedUnfairLock(initialState: Int64(0))

    func add(_ count: Int) {
        bytes.withLock { $0 += Int64(count) }
    }

    var totalBytes: Int64 {
        bytes.withLock { $0 }
    }

    // MARK: Read counters
    //
    // Feed the indexing diagnostics line: how many iCloud streaming reads
    // this run has started and how many are awaiting data right now.

    private let reads = OSAllocatedUnfairLock(initialState: (started: 0, inFlight: 0))

    /// An iCloud streaming read is about to start (permit acquired).
    func beginNetworkRead() {
        reads.withLock { $0.started += 1; $0.inFlight += 1 }
    }

    /// The read finished — success, stall, or failure.
    func endNetworkRead() {
        reads.withLock { $0.inFlight -= 1 }
    }

    /// Cumulative iCloud streaming reads started this run.
    var networkReadsStarted: Int { reads.withLock { $0.started } }

    /// iCloud streaming reads currently awaiting data.
    var networkReadsInFlight: Int { reads.withLock { $0.inFlight } }

    // MARK: Network circuit breaker
    //
    // On a device whose iCloud can't serve originals (account error, sync
    // incomplete) — or a run whose parallel streams starve each other of
    // bandwidth — network reads stall out with zero bytes. Tripping after
    // enough stalls lets the run back off the network and mark reads
    // `pendingICloud` instantly, instead of burning one stall window per
    // offloaded asset across the whole library.
    //
    // The trip signal is a **sliding window** (≥ `stallTripCount` stalls in
    // the last `stallTripThreshold` reads), not a consecutive streak: a
    // wedged iCloud still leaks the odd few bytes, and one lucky read must
    // not vouch for a dead pipe — the streak version never tripped in that
    // state, leaving the run at 0 KB/s indefinitely with no pause and no
    // banner. A mostly-healthy link (stalls well under the ratio) never
    // trips.
    //
    // The breaker is **half-open**, not permanent: after the fixed cooldown
    // it lets reads probe the network again. A probe that delivers bytes
    // closes the breaker fully; a probe that stalls re-trips it for another
    // cooldown. (The old run-permanent trip showed 0 KB/s for the rest of
    // the run and could only be cleared by cancelling and retrying by hand.)
    // No backoff by design: a failed probe costs one 8 s stall window, and
    // picking iCloud up within seconds of it recovering matters more.

    /// Window size: outcomes of this many recent network reads are kept.
    /// Small on purpose — a wedged daemon should be detected within ~a dozen
    /// reads, not after a minute of stall windows.
    static let stallTripThreshold = 12
    /// Stalls within a full window that trip the breaker (~83 %).
    static let stallTripCount = 10

    private let cooldown: Duration
    private let restDuration: Duration
    private let clock = ContinuousClock()
    private let breaker = OSAllocatedUnfairLock(
        initialState: BreakerState()
    )

    private struct BreakerState: Sendable {
        /// Outcome of the last `stallTripThreshold` reads; true = stalled.
        /// Cleared on every trip so post-cooldown probes build fresh history.
        var window: [Bool] = []
        var trippedAt: ContinuousClock.Instant?
        /// For the health log only — how many times this dead spell has
        /// re-tripped.
        var consecutiveTrips = 0
        /// Set while a single half-open probe is out; other reads keep
        /// skipping the network until its verdict. Auto-expires (see
        /// `shouldSkipNetworkRead`) in case the probe never reports back.
        var probeStartedAt: ContinuousClock.Instant?
        var totalStalls = 0
        /// New network reads hold off until this instant — a short breather
        /// started by every stall, well before the window trips.
        var restUntil: ContinuousClock.Instant?

        mutating func record(stalled: Bool) {
            window.append(stalled)
            if window.count > IndexTrafficMonitor.stallTripThreshold {
                window.removeFirst()
            }
        }

        mutating func trip(at now: ContinuousClock.Instant) {
            consecutiveTrips += 1
            trippedAt = now
            probeStartedAt = nil
            window.removeAll()
        }
    }

    init(cooldown: Duration = .seconds(30), restDuration: Duration = .seconds(2)) {
        self.cooldown = cooldown
        self.restDuration = restDuration
    }

    /// Whether the breaker is tripped and still cooling down — callers skip
    /// the network entirely. Past the cooldown this turns false (half-open):
    /// reads flow again as probes.
    var isNetworkTripped: Bool {
        let now = clock.now
        return breaker.withLock {
            guard let trippedAt = $0.trippedAt else { return false }
            return now - trippedAt < cooldown
        }
    }

    /// Time until the tripped breaker half-opens; nil when it isn't tripped
    /// (or is already probing). Drives the "retry in Ns" diagnostics line.
    var breakerCooldownRemaining: Duration? {
        let now = clock.now
        return breaker.withLock {
            guard let trippedAt = $0.trippedAt, now - trippedAt < cooldown else { return nil }
            return cooldown - (now - trippedAt)
        }
    }

    /// Final gate right before a network read starts — unlike the read-only
    /// `isNetworkTripped`, this **claims the half-open probe slot**: past the
    /// cooldown exactly one caller gets `false` (proceed, as the probe) and
    /// the rest keep getting `true` until the probe's verdict arrives via
    /// `recordNetworkStall`/`recordNetworkProgress`. Without this, every
    /// permit holder probed at once and the losers each burned a full stall
    /// window. The claim auto-expires after 15 s (probe window is 8 s) in
    /// case the probing read never reports back.
    func shouldSkipNetworkRead() -> Bool {
        let now = clock.now
        return breaker.withLock { state in
            guard let trippedAt = state.trippedAt else { return false }
            if now - trippedAt < cooldown { return true }
            if let started = state.probeStartedAt, now - started < .seconds(15) { return true }
            state.probeStartedAt = now
            return false
        }
    }

    /// Zero-byte stalls recorded this run (diagnostics).
    var stallCount: Int {
        breaker.withLock { $0.totalStalls }
    }

    /// Time left in the post-stall breather; nil when reads may start freely.
    /// Every stall pushes the breather out again — a struggling daemon gets a
    /// continuous rest, not one fixed pause.
    var networkRestRemaining: Duration? {
        let now = clock.now
        return breaker.withLock {
            guard let restUntil = $0.restUntil, restUntil > now else { return nil }
            return restUntil - now
        }
    }

    /// A network read that delivered zero bytes. Trips the breaker once
    /// `stallTripCount` of the last `stallTripThreshold` reads stalled; a
    /// stalled half-open probe re-trips for another cooldown.
    /// Returns `true` only on calls that (re-)trip it.
    /// `filename`/`elapsedMilliseconds` are for the health log only.
    @discardableResult
    func recordNetworkStall(filename: String? = nil, elapsedMilliseconds: Int? = nil) -> Bool {
        enum Outcome {
            case counted(inWindow: Int, windowSize: Int), lateDuringCooldown
            case tripped, reTripped(trips: Int)
        }
        let now = clock.now
        let (outcome, totalStalls) = breaker.withLock { state -> (Outcome, Int) in
            state.totalStalls += 1
            // First sign of a struggling daemon: give it a short breather
            // before the next read, instead of hammering on until the trip.
            state.restUntil = now + restDuration
            if let trippedAt = state.trippedAt {
                // Still cooling down: reads that were already in flight when
                // the trip happened can stall late — ignore for state.
                guard now - trippedAt >= cooldown else {
                    return (.lateDuringCooldown, state.totalStalls)
                }
                // Half-open probe stalled — re-trip for another cooldown.
                state.trip(at: now)
                return (.reTripped(trips: state.consecutiveTrips), state.totalStalls)
            }
            state.record(stalled: true)
            if state.window.count >= Self.stallTripThreshold,
               state.window.count(where: { $0 }) >= Self.stallTripCount {
                state.trip(at: now)
                return (.tripped, state.totalStalls)
            }
            return (.counted(inWindow: state.window.count(where: { $0 }), windowSize: state.window.count), state.totalStalls)
        }
        let file = filename ?? "?"
        let ms = elapsedMilliseconds.map(String.init) ?? "?"
        switch outcome {
        case .counted(let inWindow, let windowSize):
            Self.healthLogger.log("stall #\(totalStalls) (\(inWindow)/\(windowSize) in window): \(file, privacy: .public), 0 B in \(ms, privacy: .public) ms — resting new reads")
            return false
        case .lateDuringCooldown:
            Self.healthLogger.log("stall #\(totalStalls) (late, breaker already cooling): \(file, privacy: .public)")
            return false
        case .tripped:
            Self.healthLogger.log("breaker TRIPPED at stall #\(totalStalls) (\(Self.stallTripCount)+/\(Self.stallTripThreshold) recent reads stalled) — pausing iCloud reads for \(Int(self.cooldown.components.seconds))s")
            return true
        case .reTripped(let trips):
            Self.healthLogger.log("breaker RE-TRIPPED (#\(trips)): half-open probe stalled (\(file, privacy: .public)) — cooling down \(Int(self.cooldown.components.seconds))s")
            return true
        }
    }

    /// A network read that made real progress — recorded in the window, and
    /// closes a half-open breaker. Progress *during* the cooldown is ignored:
    /// up to six reads are still in flight at trip time, and any of them
    /// delivering its buffered bytes a moment later would cancel the trip
    /// and defeat the whole quiet period.
    func recordNetworkProgress() {
        let now = clock.now
        let closedByProbe = breaker.withLock { state -> Bool in
            var closed = false
            if let trippedAt = state.trippedAt {
                guard now - trippedAt >= cooldown else { return false }
                state.trippedAt = nil
                state.consecutiveTrips = 0
                state.probeStartedAt = nil
                closed = true
            }
            state.record(stalled: false)
            return closed
        }
        if closedByProbe {
            Self.healthLogger.log("breaker CLOSED: half-open probe delivered bytes — iCloud serving again")
        }
    }

    /// Called at the start of each run so the dialog counts this run only and
    /// the breaker starts closed.
    func reset() {
        bytes.withLock { $0 = 0 }
        reads.withLock { $0 = (0, 0) }
        breaker.withLock { $0 = BreakerState() }
    }
}

/// One sample of network state shown in the indexing progress UI.
struct IndexNetworkStatus: Equatable, Sendable {
    var connection: NetworkConnectionType
    var bytesDownloaded: Int64
    /// nil until two samples exist (no delta to compute yet).
    var bytesPerSecond: Int64?
    /// Whether this run may stream from iCloud at all. Kept for callers/tests;
    /// the display always shows speed + total now (see `displayLine`).
    var isNetworkAllowed: Bool = false

    /// True when iCloud streaming is held back because we're on a metered
    /// cellular path the user hasn't opted into — local metadata reads still
    /// proceed (they cost no data), but iCloud-only photos wait for Wi-Fi.
    var isStreamingPaused: Bool {
        !isNetworkAllowed && connection == .cellular
    }

    /// `Wi-Fi · 1.2 MB/s · 45 MB`. Speed and downloaded total are dropped
    /// when zero — a local-only run reads just `Wi-Fi`, and stats appear
    /// only once real iCloud traffic starts. On an unpermitted cellular path
    /// it reads `Cellular · Paused — Wi-Fi needed`.
    var displayLine: String {
        if isStreamingPaused {
            return "\(connection.displayName) · " + String(localized: "Paused — Wi-Fi needed")
        }
        var parts = [connection.displayName]
        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append(Self.byteString(bytesPerSecond) + "/s")
        }
        if bytesDownloaded > 0 {
            parts.append(Self.byteString(bytesDownloaded))
        }
        return parts.joined(separator: " · ")
    }

    /// Like `displayLine` but always shows speed and downloaded total, even at
    /// zero (`Wi-Fi · 0 KB/s · 0 KB`). Used on the dim overlay, where a stable,
    /// always-present network readout is wanted rather than one that appears
    /// only once traffic starts.
    var detailedLine: String {
        if isStreamingPaused {
            return "\(connection.displayName) · " + String(localized: "Paused — Wi-Fi needed")
        }
        return [
            connection.displayName,
            Self.byteString(bytesPerSecond ?? 0) + "/s",
            Self.byteString(bytesDownloaded)
        ].joined(separator: " · ")
    }

    private static func byteString(_ value: Int64) -> String {
        // Numeric zero ("0 KB/s"), not ByteCountFormatter's default "Zero KB".
        Self.formatter.string(fromByteCount: value)
    }

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

/// One sample of pipeline diagnostics shown in the indexing progress UI,
/// alongside `IndexNetworkStatus`: device thermal state (which throttles the
/// read fan-out), and how many iCloud streaming reads are in flight — the
/// answer to "is the run over-requesting or starving?".
struct IndexDiagnostics: Equatable, Sendable {
    var thermalState: ProcessInfo.ThermalState
    /// Reader fan-out the pipeline uses at this thermal/power state.
    var readConcurrency: Int
    /// Low Power Mode caps the fan-out; surfaced so the displayed reader
    /// count is explainable.
    var isLowPowerMode: Bool
    var networkReadsStarted: Int
    var networkReadsInFlight: Int
    /// Zero-byte stalls this run.
    var stallCount: Int
    /// Set while the iCloud circuit breaker is cooling down.
    var breakerCooldownRemaining: Duration?

    /// `Thermal: Fair · 6 readers` — with ` · Low Power` appended while
    /// Low Power Mode is on.
    var thermalLine: String {
        var line = "Thermal: \(thermalState.displayName) · \(readConcurrency) readers"
        if isLowPowerMode {
            line += " · Low Power"
        }
        return line
    }

    /// `iCloud: 4 in flight · 132 requested` — with ` · 12 stalls` appended
    /// once any read has stalled, and replaced by
    /// `iCloud paused · retry in 42s` while the breaker cools down.
    var iCloudLine: String {
        if let breakerCooldownRemaining {
            let seconds = max(0, Int(breakerCooldownRemaining.components.seconds))
            return "iCloud paused · retry in \(seconds)s"
        }
        var line = "iCloud: \(networkReadsInFlight) in flight · \(networkReadsStarted) requested"
        if stallCount > 0 {
            line += " · \(stallCount) stalls"
        }
        return line
    }
}

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
