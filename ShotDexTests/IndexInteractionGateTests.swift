import Testing
@testable import ShotDex

/// Pure gate logic — refcount pairing and the inactivity auto-resume deadline
/// (checked via the injectable `now` overload).
struct IndexInteractionGateTests {

    @Test func beginPausesEndReleases() {
        let gate = IndexInteractionGate()
        #expect(!gate.shouldPauseIndexing)
        gate.beginInteraction()
        #expect(gate.shouldPauseIndexing)
        gate.endInteraction()
        #expect(!gate.shouldPauseIndexing)
    }

    @Test func refcountNeedsMatchingEnds() {
        let gate = IndexInteractionGate()
        gate.beginInteraction()
        gate.beginInteraction()
        gate.endInteraction()
        #expect(gate.shouldPauseIndexing)
        gate.endInteraction()
        #expect(!gate.shouldPauseIndexing)
    }

    @Test func extraEndClampsAtZero() {
        let gate = IndexInteractionGate()
        gate.endInteraction()
        gate.endInteraction()
        #expect(!gate.shouldPauseIndexing)
        // A negative count would swallow this begin.
        gate.beginInteraction()
        #expect(gate.shouldPauseIndexing)
    }

    @Test func pauseExpiresAfterMaxDuration() {
        let gate = IndexInteractionGate()
        gate.beginInteraction()
        let start = ContinuousClock.now
        #expect(gate.shouldPauseIndexing(now: start))
        #expect(gate.shouldPauseIndexing(now: start + IndexInteractionGate.maxPauseDuration - .seconds(1)))
        #expect(!gate.shouldPauseIndexing(now: start + IndexInteractionGate.maxPauseDuration + .seconds(1)))
    }

    @Test func touchExtendsDeadline() {
        let gate = IndexInteractionGate()
        gate.beginInteraction()
        let start = ContinuousClock.now
        // Activity at +60 s pushes the deadline to +150 s.
        gate.touch(now: start + .seconds(60))
        #expect(gate.shouldPauseIndexing(now: start + .seconds(120)))
        #expect(!gate.shouldPauseIndexing(now: start + .seconds(151)))
    }

    @Test func expiredPauseResumesOnNewActivity() {
        let gate = IndexInteractionGate()
        gate.beginInteraction()
        let start = ContinuousClock.now
        let expired = start + IndexInteractionGate.maxPauseDuration + .seconds(1)
        #expect(!gate.shouldPauseIndexing(now: expired))
        gate.touch(now: expired)
        #expect(gate.shouldPauseIndexing(now: expired + .seconds(1)))
    }
}
