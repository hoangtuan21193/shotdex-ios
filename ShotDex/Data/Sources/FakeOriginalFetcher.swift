#if DEBUG
import Foundation
import os
import Photos

/// A scripted iCloud library for a simulator, which has none (FS-02.06 plan
/// §4). Photos it calls "in iCloud" answer the probe as such and download
/// over a set time with steady progress; everything else, and the bytes of a
/// finished download, come from `base` — PhotoKit on a simulator, where
/// every photo is local, or a fixture writer in the tests.
///
/// The script is the value of `-ShotDexFakeICloud`, a comma-separated list:
/// - `cloud=all` · `cloud=none` · `cloud=<n>` (the first n photos asked about)
/// - `seconds=<s>` — one download's length (default 6)
/// - `fail=<k>[+<k>…]` — the k-th download (from 1, in start order) fails
///   with a network error at 40%
/// - `stall` — downloads stay at 0% until cancelled
/// - `denied` — a download fails with Photos' access error
/// - `mb=<n>` — every photo's original is n MB (for the space check)
/// - `free=<n>` — the device has n MB free
final class FakeOriginalFetcher: OriginalFetching, @unchecked Sendable {
    struct Script: Equatable, Sendable {
        enum Cloud: Equatable, Sendable { case all, none, first(Int) }
        var cloud: Cloud = .all
        var seconds: Double = 6
        var failing: Set<Int> = []
        var stalls = false
        var denied = false
        var megabytes: Int64?
        var freeMegabytes: Int64?

        init() {}

        init(_ text: String) {
            for part in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                let key = pair[0], value = pair.count > 1 ? pair[1] : ""
                switch key {
                case "cloud":
                    cloud = value == "none" ? .none : Int(value).map(Cloud.first) ?? .all
                case "seconds": seconds = Double(value) ?? seconds
                case "fail": failing = Set(value.split(separator: "+").compactMap { Int($0) })
                case "stall": stalls = true
                case "denied": denied = true
                case "mb": megabytes = Int64(value)
                case "free": freeMegabytes = Int64(value)
                default: break
                }
            }
        }
    }

    /// The script in the launch arguments, if any.
    static func fromLaunchArguments(base: any OriginalFetching) -> FakeOriginalFetcher? {
        guard let text = UserDefaults.standard.string(forKey: "ShotDexFakeICloud") else { return nil }
        return FakeOriginalFetcher(script: Script(text), base: base)
    }

    let script: Script
    private let base: any OriginalFetching

    private struct State {
        var seen: [String] = []
        var downloaded: Set<String> = []
        var started = 0
        var fetchCount = 0
        var transferCount = 0
        var cancelledCount = 0
        var running = 0
        var peakRunning = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(script: Script, base: any OriginalFetching) {
        self.script = script
        self.base = base
    }

    /// Downloads of photos "in iCloud" started so far — the number a test
    /// holds at 0 until a destination asks.
    var downloadCount: Int { state.withLock { $0.started } }
    /// Every `fetch`, the local ones included.
    var fetchCount: Int { state.withLock { $0.fetchCount } }
    var cancelledCount: Int { state.withLock { $0.cancelledCount } }
    /// The most downloads that ran at once.
    var peakConcurrency: Int { state.withLock { $0.peakRunning } }

    /// The device's free space under this script, when it sets one.
    var freeBytes: Int64? { script.freeMegabytes.map { $0 * 1_000_000 } }

    func isInCloud(_ id: String) -> Bool {
        state.withLock { state in
            if !state.seen.contains(id) { state.seen.append(id) }
            guard !state.downloaded.contains(id) else { return false }
            switch script.cloud {
            case .all: return true
            case .none: return false
            case .first(let count): return (state.seen.firstIndex(of: id) ?? .max) < count
            }
        }
    }

    func probe(_ item: OriginalItem) async -> OriginalAvailability {
        if isInCloud(item.id) { return .inCloud }
        return await base.probe(item)
    }

    func byteCount(of item: OriginalItem) async -> Int64? {
        if let megabytes = script.megabytes { return megabytes * 1_000_000 }
        return await base.byteCount(of: item)
    }

    func fetch(_ item: OriginalItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        state.withLock { $0.fetchCount += 1 }
        if isInCloud(item.id) {
            try await play(item.id, progress: progress)
        }
        try await base.fetch(item, to: url, progress: { _ in })
        progress(1)
    }

    func scriptedTransfer(for id: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard isInCloud(id) else { return }
        state.withLock { $0.transferCount += 1 }
        try await play(id, progress: progress)
    }

    /// One scripted download: steady ticks over `seconds`, a failure at 40%
    /// for the k-th, or 0% forever. Cancelling stops it at the next tick.
    private func play(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let ordinal = state.withLock { state in
            state.started += 1
            state.running += 1
            state.peakRunning = max(state.peakRunning, state.running)
            return state.started
        }
        defer { state.withLock { $0.running -= 1 } }
        let ticks = max(1, Int(script.seconds * 10))
        do {
            var tick = 0
            while true {
                try Task.checkCancellation()
                let fraction = script.stalls ? 0 : min(1, Double(tick) / Double(ticks))
                if script.failing.contains(ordinal), fraction >= 0.4 {
                    throw NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.networkError.rawValue)
                }
                if script.denied, fraction >= 0.3 {
                    throw NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.accessUserDenied.rawValue)
                }
                progress(fraction)
                if !script.stalls, tick >= ticks { break }
                try await Task.sleep(for: .milliseconds(100))
                tick += 1
            }
        } catch is CancellationError {
            state.withLock { $0.cancelledCount += 1 }
            throw CancellationError()
        }
        state.withLock { _ = $0.downloaded.insert(id) }
    }
}
#endif
