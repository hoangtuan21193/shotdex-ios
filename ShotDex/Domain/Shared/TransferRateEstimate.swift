import Foundation

/// Time left from the speed of the last 30 seconds (FS-15.02 §6): a byte
/// count sampled as it grows. Nothing for the first 2 seconds — a guess
/// from one block is worse than no guess.
struct TransferRateEstimate: Sendable, Equatable {
    static let window: TimeInterval = 30
    static let warmUp: TimeInterval = 2

    private var samples: [(time: Date, bytes: Int64)] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.samples.map(\.bytes) == rhs.samples.map(\.bytes) && lhs.samples.map(\.time) == rhs.samples.map(\.time)
    }

    mutating func record(_ bytes: Int64, at now: Date = Date()) {
        samples.append((now, bytes))
        samples.removeAll { now.timeIntervalSince($0.time) > Self.window }
    }

    /// Bytes a second over the window, once it is long enough.
    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= Self.warmUp else { return nil }
        let rate = Double(last.bytes - first.bytes) / span
        return rate > 0 ? rate : nil
    }

    func secondsLeft(total: Int64) -> TimeInterval? {
        guard let rate = bytesPerSecond, let last = samples.last else { return nil }
        return max(0, Double(total - last.bytes) / rate)
    }
}
