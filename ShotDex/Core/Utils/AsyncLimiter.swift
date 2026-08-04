import Foundation

/// A counting semaphore for Swift Concurrency: at most `limit` callers run
/// `withPermit` bodies concurrently; the rest suspend in FIFO order.
///
/// Used to cap concurrent iCloud streaming reads below the pipeline's total
/// read fan-out — parallel network streams starve each other of bandwidth
/// long before parallel local reads contend on anything.
///
/// Waiting for a permit is **cancellable**. It did not used to be: a queued
/// caller parked in a bare continuation, so cancelling an index run left every
/// waiter suspended forever, the run never returned from its `operation`, and
/// `LibraryModel`'s reentrancy latch stayed set — indexing was dead until the
/// app was force-quit.
actor AsyncLimiter {
    private let limit: Int
    private var active = 0
    /// FIFO. Keyed so a cancelled waiter can be pulled out of the middle.
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    /// Runs `body` while holding a permit. Returns nil — **without** running
    /// `body` — when the calling task is cancelled before a permit frees up.
    func withPermit<T: Sendable>(_ body: @Sendable () async -> T) async -> T? {
        guard await acquire() else { return nil }
        defer { release() }
        return await body()
    }

    /// False when the caller was cancelled while queued: it holds no permit and
    /// must not release one.
    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if active < limit {
            active += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancelled between the check above and parking here, so
                // `onCancel` has already run and found nothing to wake: resume
                // now or this waiter is lost.
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            // The releaser hands its slot over without touching `active`, so a
            // fresh caller can't slip in between a decrement here and an
            // increment there.
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }
}
