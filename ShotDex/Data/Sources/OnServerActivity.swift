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
        /// The newest file in flight.
        var fileName: String?
        /// That file's progress.
        var bytesDone: Int64
        var bytesTotal: Int64?
        /// Bytes per second over every file in flight — the check downloads
        /// several originals at once; nil until measured or when nothing
        /// has moved for a few seconds.
        var bytesPerSecond: Double?
        var startedAt: Date
        /// Files in flight besides `fileName`.
        var otherFiles = 0
    }

    private struct Transfer {
        var kind: Kind
        var fileName: String?
        var bytesDone: Int64 = 0
        var bytesTotal: Int64?
        var startedAt: Date
        var order: Int
    }

    private struct State {
        /// In flight, by the key the pass gave `begin`.
        var transfers: [String: Transfer] = [:]
        /// Listing or between files, when nothing is in flight.
        var idle: (kind: Kind, startedAt: Date)?
        var nextOrder = 0
        /// Every byte any transfer moved, for the shared rate.
        var movedBytes: Int64 = 0
        var lastSample: (time: ContinuousClock.Instant, bytes: Int64)?
        var lastProgress: ContinuousClock.Instant?
        var bytesPerSecond: Double?
    }

    /// Past this without a byte, the speed is not shown — a stalled download
    /// must not keep displaying the speed it once had.
    static let staleRate: Duration = .seconds(3)

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let clock = ContinuousClock()

    var current: Snapshot? {
        let now = clock.now
        return state.withLock { state in
            let rate = state.lastProgress.map { now - $0 < Self.staleRate } == true ? state.bytesPerSecond : nil
            if let newest = state.transfers.values.max(by: { $0.order < $1.order }) {
                return Snapshot(kind: newest.kind, fileName: newest.fileName, bytesDone: newest.bytesDone,
                                bytesTotal: newest.bytesTotal, bytesPerSecond: rate, startedAt: newest.startedAt,
                                otherFiles: state.transfers.count - 1)
            }
            guard let idle = state.idle else { return nil }
            return Snapshot(kind: idle.kind, fileName: nil, bytesDone: 0, bytesTotal: nil,
                            bytesPerSecond: nil, startedAt: idle.startedAt)
        }
    }

    /// A listing or other step that moves no file.
    func begin(_ kind: Kind) {
        state.withLock { $0.idle = (kind, Date()) }
    }

    /// A file starts moving. `key` names it until `end(key)` — several run
    /// at once, and each reports its own bytes.
    func begin(_ kind: Kind, key: String, fileName: String?, bytesTotal: Int64?) {
        let now = clock.now
        state.withLock { state in
            state.nextOrder += 1
            state.transfers[key] = Transfer(kind: kind, fileName: fileName, bytesTotal: bytesTotal,
                                            startedAt: Date(), order: state.nextOrder)
            if state.lastSample == nil { state.lastSample = (now, state.movedBytes) }
        }
    }

    /// `bytes`: done so far in the file `key`.
    func progress(_ key: String, _ bytes: Int64) {
        let now = clock.now
        state.withLock { state in
            guard var transfer = state.transfers[key] else { return }
            let moved = bytes - transfer.bytesDone
            if moved > 0 { state.movedBytes += moved }
            transfer.bytesDone = bytes
            state.transfers[key] = transfer
            state.lastProgress = now
            guard let last = state.lastSample else {
                state.lastSample = (now, state.movedBytes)
                return
            }
            let elapsed = last.time.duration(to: now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            guard seconds >= 0.5 else { return }
            let rate = Double(state.movedBytes - last.bytes) / seconds
            // Smoothed, so the figure does not jump with each chunk.
            state.bytesPerSecond = state.bytesPerSecond.map { $0 * 0.6 + rate * 0.4 } ?? rate
            state.lastSample = (now, state.movedBytes)
        }
    }

    func end(_ key: String) {
        state.withLock { state in
            state.transfers[key] = nil
            if state.transfers.isEmpty { state.idle = (.working(""), Date()) }
        }
    }

    func clear() {
        state.withLock { $0 = State() }
    }
}

extension OnServerActivity {
    /// The key a Photos original's download reports under — the same on the
    /// side that starts it and inside the exporter's progress callback.
    static func downloadKey(assetId: String, fileKey: String) -> String {
        "photos|\(assetId)|\(fileKey)"
    }
}
