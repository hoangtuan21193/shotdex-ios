import Foundation
import os
import Testing
@testable import ShotDex

/// The iCloud stream cap: concurrency never exceeds the limit, nobody is lost,
/// and a cancelled waiter never stays parked.
struct AsyncLimiterTests {

    @Test func neverExceedsLimit() async {
        let limiter = AsyncLimiter(limit: 2)
        let gauge = OSAllocatedUnfairLock(initialState: (current: 0, peak: 0))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = await limiter.withPermit {
                        gauge.withLock {
                            $0.current += 1
                            $0.peak = max($0.peak, $0.current)
                        }
                        try? await Task.sleep(for: .milliseconds(5))
                        gauge.withLock { $0.current -= 1 }
                    }
                }
            }
        }
        #expect(gauge.withLock { $0.peak } <= 2)
        #expect(gauge.withLock { $0.current } == 0)
    }

    @Test func allCallersCompleteWithTheirOwnResult() async {
        let limiter = AsyncLimiter(limit: 3)
        let results = await withTaskGroup(of: Int.self, returning: Set<Int>.self) { group in
            for value in 0..<50 {
                group.addTask { await limiter.withPermit { value } ?? -1 }
            }
            var out = Set<Int>()
            for await value in group { out.insert(value) }
            return out
        }
        #expect(results == Set(0..<50))
    }

    /// The regression that left indexing dead until the app was force-quit: a
    /// waiter parked for a permit ignored cancellation, so a cancelled index run
    /// never returned from its pipeline call and never cleared its own latch.
    @Test func cancellingAQueuedCallerResumesItAndRunsNoBody() async {
        let limiter = AsyncLimiter(limit: 1)
        let holderHasPermit = Gate()
        let holderMayFinish = Gate()
        let bodyRan = OSAllocatedUnfairLock(initialState: false)

        let holder = Task {
            await limiter.withPermit {
                await holderHasPermit.open()
                await holderMayFinish.wait()
            }
        }
        await holderHasPermit.wait()

        // The only permit is taken, so this one queues.
        let queued = Task {
            await limiter.withPermit { () -> Int in
                bodyRan.withLock { $0 = true }
                return 1
            }
        }
        queued.cancel()
        #expect(await queued.value == nil)
        #expect(bodyRan.withLock { $0 } == false)

        await holderMayFinish.open()
        _ = await holder.value

        // A cancelled waiter must not release a permit it never held, or the
        // limiter over-grants from here on.
        #expect(await limiter.withPermit { 7 } == 7)
    }
}

/// One-shot async gate, so the tests above order their tasks without sleeping.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
