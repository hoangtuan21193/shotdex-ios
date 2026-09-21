import Foundation

/// A counter that caps how many of something may run at once, and says no
/// rather than queueing.
///
/// Used for iCloud thumbnail downloads: a caller that cannot get a slot is
/// told immediately, so the tile keeps its soft rendition and asks again at
/// the next scroll-stop. Queueing would be worse — the queue would be full of
/// tiles that have long since scrolled away.
final class ConcurrencyGate: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var inFlight = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// True when a slot was taken. Every true must be paired with `release()`.
    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight < limit else { return false }
        inFlight += 1
        return true
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        inFlight = max(0, inFlight - 1)
    }

    /// For tests and diagnostics.
    var currentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
    }
}
