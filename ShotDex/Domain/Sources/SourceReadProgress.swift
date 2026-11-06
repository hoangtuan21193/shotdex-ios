import Foundation
import os

/// A folder or drive being read (FS-19.01 §4): what the grid's banner, the
/// source's sidebar row and the sidebar foot say about it.
struct SourceReadProgress: Equatable, Sendable, Codable {
    let sourceId: String
    let sourceName: String
    /// The first read after Add: "Adding “…”"; a later read says "Reading".
    let isAdding: Bool
    var done = 0
    var total = 0
    var estimate = IndexEstimate()
    private enum CodingKeys: String, CodingKey { case sourceId, sourceName, isAdding, done, total, isPaused, isDisconnected }
    /// Pause took effect: what was read stays; Resume reads only the rest.
    var isPaused = false
    /// The drive went away mid-read (FS-19.01b §2): what was read stays, the
    /// rest waits for the drive.
    var isDisconnected = false

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// "Adding “Client Shoots 2026”".
    var title: String {
        if isDisconnected {
            return String(localized: "\(sourceName) was disconnected", comment: "Source read banner: the drive went away mid-read")
        }
        if isPaused {
            return String(localized: "Adding “\(sourceName)” is paused", comment: "Source read banner: paused")
        }
        return isAdding
            ? String(localized: "Adding “\(sourceName)”", comment: "Source read banner: the first read of a new source")
            : String(localized: "Reading “\(sourceName)”", comment: "Source read banner: a source read again")
    }

    /// "1,240 of 3,812 photos read · about 2 min left" — "Estimating time…"
    /// before the first 200 files, no time while paused.
    func detail(now: Date = Date()) -> String {
        let read = String(localized: "\(done) of \(total) photos read", comment: "Source read banner: files read so far (plural)")
        if isDisconnected {
            return read + " · " + String(localized: "connect it to read the rest", comment: "Source read banner: the drive went away mid-read")
        }
        if isPaused { return read }
        let left = estimate.secondsLeft(remaining: total - done).map(Self.timeLeft)
            ?? String(localized: "Estimating time…", comment: "Source read banner: no time estimate yet")
        return "\(read) · \(left)"
    }

    /// "Indexing 1,240 of 3,812" — the sidebar foot; "Paused · …" once paused.
    var footLine: String {
        if isPaused || isDisconnected {
            return String(localized: "Paused · \(done) of \(total)", comment: "Mac sidebar foot: a source read paused (plural)")
        }
        return footLineRunning
    }

    private var footLineRunning: String {
        String(localized: "Indexing \(done) of \(total)", comment: "Mac sidebar foot: a source being read (plural)")
    }

    /// Whole minutes, never seconds: "about 2 min left", "about 1 h 20 min left".
    static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        guard minutes >= 60 else {
            return String(localized: "about \(minutes) min left", comment: "Source read: time left in minutes")
        }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0
            ? String(localized: "about \(hours) h left", comment: "Source read: time left in whole hours")
            : String(localized: "about \(hours) h \(rest) min left", comment: "Source read: time left in hours and minutes")
    }
}

/// The read's Pause switch and its progress throttle, shared between the
/// main actor (the button) and the runner's actor (the loop).
final class SourceReadControl: Sendable {
    private struct State {
        var isPaused = false
        var lastReport = Date.distantPast
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func reset() { state.withLock { $0 = State() } }
    func pause() { state.withLock { $0.isPaused = true } }
    var isPaused: Bool { state.withLock { $0.isPaused } }

    /// At most ten reports a second, and always the first and the last: a
    /// hop to the main actor per file would be 3,812 of them.
    func shouldReport(done: Int, total: Int, now: Date = Date()) -> Bool {
        state.withLock {
            guard done == 0 || done >= total || now.timeIntervalSince($0.lastReport) >= 0.1 else { return false }
            $0.lastReport = now
            return true
        }
    }
}
