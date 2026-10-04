import Foundation

/// Time left for an index run — the Photos library and every folder, drive
/// and server source count the same way (FS-19 01 §4). The speed is the one
/// over the last 200 items, so a run that slows down (iCloud originals, a
/// network drive) shows it within 200 items; before the first 200 there is
/// no number at all, because a guess from a handful of files is worse than
/// none ("Estimating time…").
struct IndexEstimate: Sendable, Equatable {
    static let window = 200

    private var samples: [Sample] = []

    private struct Sample: Sendable, Equatable {
        let processed: Int
        let time: Date
    }

    /// Feeds the run's running count; call it as often as progress arrives.
    mutating func record(processed: Int, at now: Date = Date()) {
        if let last = samples.last, processed < last.processed {
            samples.removeAll()
        }
        samples.append(Sample(processed: processed, time: now))
        // Keep the newest sample at or before the window start and
        // everything after it — enough to measure exactly 200 items back.
        let floor = processed - Self.window
        if let keepFrom = samples.lastIndex(where: { $0.processed <= floor }), keepFrom > 0 {
            samples.removeFirst(keepFrom)
        }
    }

    /// Items a second over the last 200, once this run has done 200.
    var itemsPerSecond: Double? {
        guard let first = samples.first, let last = samples.last,
              last.processed - first.processed >= Self.window else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span > 0 else { return nil }
        return Double(last.processed - first.processed) / span
    }

    /// Nil until the estimate exists.
    func secondsLeft(remaining: Int) -> TimeInterval? {
        guard let rate = itemsPerSecond, rate > 0 else { return nil }
        return Double(max(0, remaining)) / rate
    }
}
