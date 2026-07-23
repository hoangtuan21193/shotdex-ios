import Foundation

/// A counting semaphore for Swift Concurrency: at most `limit` callers run
/// `withPermit` bodies concurrently; the rest suspend in FIFO order.
///
/// Used to cap concurrent iCloud streaming reads below the pipeline's total
/// read fan-out — parallel network streams starve each other of bandwidth
/// long before parallel local reads contend on anything.
actor AsyncLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func withPermit<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await body()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        // The releaser hands its slot over without touching `active`, so a
        // fresh caller can't slip in between a decrement here and an
        // increment there.
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
