import Foundation
import os

/// Counts bytes streamed from iCloud during an index run. `ExifService`
/// reports every received chunk; the indexing UI polls the total once a
/// second to derive a download speed.
final class IndexTrafficMonitor: Sendable {
    private let bytes = OSAllocatedUnfairLock(initialState: Int64(0))

    func add(_ count: Int) {
        bytes.withLock { $0 += Int64(count) }
    }

    var totalBytes: Int64 {
        bytes.withLock { $0 }
    }

    // MARK: Network circuit breaker
    //
    // On a device whose iCloud can't serve originals (account error, sync
    // incomplete), every network read stalls out with zero bytes. Counting
    // consecutive zero-byte stalls lets the run give up on the network after
    // a threshold and mark the rest `pendingICloud` instantly, instead of
    // burning one stall window per offloaded asset across the whole library.
    // A single byte of real progress resets the count, so a briefly flaky
    // link never trips it.

    /// Consecutive network stalls threshold beyond which the network is
    /// treated as down for the remainder of the run.
    static let stallTripThreshold = 24

    private let breaker = OSAllocatedUnfairLock(initialState: (consecutiveStalls: 0, tripped: false))

    /// Whether the breaker has tripped — callers skip the network entirely.
    var isNetworkTripped: Bool {
        breaker.withLock { $0.tripped }
    }

    /// A network read that delivered zero bytes. Trips the breaker once
    /// `stallTripThreshold` of these accumulate without an intervening success.
    /// Returns `true` only on the call that flips it from closed to tripped.
    @discardableResult
    func recordNetworkStall() -> Bool {
        breaker.withLock {
            guard !$0.tripped else { return false }
            $0.consecutiveStalls += 1
            if $0.consecutiveStalls >= Self.stallTripThreshold {
                $0.tripped = true
                return true
            }
            return false
        }
    }

    /// A network read that made real progress — resets the stall streak.
    func recordNetworkProgress() {
        breaker.withLock { $0.consecutiveStalls = 0 }
    }

    /// Called at the start of each run so the dialog counts this run only and
    /// the breaker starts closed.
    func reset() {
        bytes.withLock { $0 = 0 }
        breaker.withLock { $0 = (0, false) }
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
    var allowsNetwork: Bool = false

    /// `Wi-Fi · 1.2 MB/s · 45 MB`. Speed and downloaded total are dropped
    /// when zero — a local-only run reads just `Wi-Fi`, and stats appear
    /// only once real iCloud traffic starts.
    var displayLine: String {
        var parts = [connection.displayName]
        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append(Self.byteString(bytesPerSecond) + "/s")
        }
        if bytesDownloaded > 0 {
            parts.append(Self.byteString(bytesDownloaded))
        }
        return parts.joined(separator: " · ")
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
