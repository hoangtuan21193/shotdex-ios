import Foundation
import os

/// What the on-server check is doing this second — the file it downloads
/// or reads, how far, and how fast — for the smart album's popover (user
/// 2026-11-11: "the popover must say which file is downloading, with the
/// network speed"). Written from the passes on any thread, read by the
/// screen once a second; nothing is stored.
final class OnServerActivity: @unchecked Sendable {
    static let shared = OnServerActivity()

    enum Kind: Sendable, Equatable {
        /// Listing a server source's files.
        case listing(source: String)
        /// Downloading a Photos original from iCloud to hash it.
        case downloading
        /// Reading a server file to hash it.
        case reading
        /// Between files: comparing, merging, the hash ledger.
        case working(String)
    }

    struct Snapshot: Sendable, Equatable {
        var kind: Kind
        var fileName: String?
        var bytesDone: Int64
        var bytesTotal: Int64?
        /// Bytes per second over the last few seconds; nil until measured.
        var bytesPerSecond: Double?
        var startedAt: Date
    }

    private struct State {
        var snapshot: Snapshot?
        var lastSample: (time: ContinuousClock.Instant, bytes: Int64)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let clock = ContinuousClock()

    var current: Snapshot? { state.withLock { $0.snapshot } }

    func begin(_ kind: Kind, fileName: String? = nil, bytesTotal: Int64? = nil) {
        let now = clock.now
        state.withLock {
            $0.snapshot = Snapshot(kind: kind, fileName: fileName, bytesDone: 0, bytesTotal: bytesTotal,
                                   bytesPerSecond: $0.snapshot?.bytesPerSecond, startedAt: Date())
            $0.lastSample = (now, 0)
        }
    }

    /// `bytes`: done so far in the current file.
    func progress(_ bytes: Int64) {
        let now = clock.now
        state.withLock {
            guard var snapshot = $0.snapshot else { return }
            if let last = $0.lastSample {
                let seconds = Double(last.time.duration(to: now).components.attoseconds) / 1e18
                    + Double(last.time.duration(to: now).components.seconds)
                if seconds >= 0.5, bytes >= last.bytes {
                    let rate = Double(bytes - last.bytes) / seconds
                    // Smoothed, so the figure does not jump with each chunk.
                    snapshot.bytesPerSecond = snapshot.bytesPerSecond.map { $0 * 0.6 + rate * 0.4 } ?? rate
                    $0.lastSample = (now, bytes)
                }
            }
            snapshot.bytesDone = bytes
            $0.snapshot = snapshot
        }
    }

    func end() {
        state.withLock {
            // The speed outlives the file, so the next one starts with it.
            if var snapshot = $0.snapshot {
                snapshot.kind = .working("")
                snapshot.fileName = nil
                snapshot.bytesDone = 0
                snapshot.bytesTotal = nil
                $0.snapshot = snapshot
            }
        }
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}
