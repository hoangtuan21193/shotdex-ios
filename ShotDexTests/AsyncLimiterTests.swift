import Foundation
import os
import Testing
@testable import ShotDex

/// The iCloud stream cap: concurrency never exceeds the limit, nobody is lost.
struct AsyncLimiterTests {

    @Test func neverExceedsLimit() async {
        let limiter = AsyncLimiter(limit: 2)
        let gauge = OSAllocatedUnfairLock(initialState: (current: 0, peak: 0))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await limiter.withPermit {
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
                group.addTask { await limiter.withPermit { value } }
            }
            var out = Set<Int>()
            for await value in group { out.insert(value) }
            return out
        }
        #expect(results == Set(0..<50))
    }
}
