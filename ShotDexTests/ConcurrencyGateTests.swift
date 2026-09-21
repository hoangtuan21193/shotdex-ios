import Foundation
import Testing
@testable import ShotDex

/// The cap on how many iCloud thumbnail downloads run at once.
///
/// A library kept in iCloud shows a screenful of Optimize Storage proxies, and
/// every one of them wanted its own download the moment scrolling stopped. The
/// gate turns that into a few at a time, and says no rather than queueing — a
/// queued tile is usually one that has already scrolled away.
struct ConcurrencyGateTests {
    @Test func itAllowsUpToTheLimitAndThenRefuses() {
        let gate = ConcurrencyGate(limit: 3)
        #expect(gate.tryAcquire())
        #expect(gate.tryAcquire())
        #expect(gate.tryAcquire())
        #expect(!gate.tryAcquire())
        #expect(gate.currentCount == 3)
    }

    @Test func aReleasedSlotIsReused() {
        let gate = ConcurrencyGate(limit: 1)
        #expect(gate.tryAcquire())
        #expect(!gate.tryAcquire())
        gate.release()
        #expect(gate.currentCount == 0)
        #expect(gate.tryAcquire())
    }

    /// A release without a matching acquire — a completion that fired twice, a
    /// cancelled request — must not lend out slots that do not exist.
    @Test func releasingMoreThanWasTakenCannotGoNegative() {
        let gate = ConcurrencyGate(limit: 2)
        gate.release()
        gate.release()
        #expect(gate.currentCount == 0)
        #expect(gate.tryAcquire())
        #expect(gate.tryAcquire())
        #expect(!gate.tryAcquire())
    }

    @Test func aLimitBelowOneStillAllowsOne() {
        let gate = ConcurrencyGate(limit: 0)
        #expect(gate.tryAcquire())
        #expect(!gate.tryAcquire())
    }

    /// Acquires and releases from many threads at once must leave the count
    /// where it started.
    @Test func itHoldsUpUnderConcurrentUse() async {
        let gate = ConcurrencyGate(limit: 4)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    if gate.tryAcquire() {
                        gate.release()
                    }
                }
            }
        }
        #expect(gate.currentCount == 0)
    }
}
