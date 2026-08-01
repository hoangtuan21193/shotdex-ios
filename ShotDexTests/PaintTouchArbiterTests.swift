import CoreGraphics
import Foundation
import Testing

@testable import ShotDex

struct PaintTouchArbiterTests {
    @Test func aPinchThatLandsOneFingerFirstLeavesNoTrace() {
        var arbiter = PaintTouchArbiter()
        #expect(arbiter.touchDown(activeTouches: 1, at: .zero, time: 0) == .track(.zero))
        // The second finger of a pinch, 30ms behind the first: inside the
        // confirmation window, so the stroke was never written.
        #expect(arbiter.extraFingerDown(time: 0.03) == .ignore)
    }

    @Test func aTapPaintsExactlyOneDabEvenInsideTheConfirmationWindow() {
        var arbiter = PaintTouchArbiter()
        let point = CGPoint(x: 10, y: 12)
        _ = arbiter.touchDown(activeTouches: 1, at: point, time: 0)
        // A finger that has lifted cannot become a pinch, so it paints.
        #expect(arbiter.touchUp(time: 0.02) == .begin([point]))
    }

    @Test func movingFarEnoughConfirmsBeforeTheDelayIsUp() {
        var arbiter = PaintTouchArbiter()
        _ = arbiter.touchDown(activeTouches: 1, at: .zero, time: 0)
        let moved = CGPoint(x: 5, y: 0)
        #expect(arbiter.touchMoved(to: moved, time: 0.01) == .begin([.zero, moved]))
    }

    @Test func waitingLongEnoughConfirmsWithoutMoving() {
        var arbiter = PaintTouchArbiter()
        _ = arbiter.touchDown(activeTouches: 1, at: .zero, time: 0)
        let moved = CGPoint(x: 1, y: 0)
        #expect(arbiter.touchMoved(to: moved, time: 0.1) == .begin([.zero, moved]))
        let next = CGPoint(x: 2, y: 0)
        #expect(arbiter.touchMoved(to: next, time: 0.11) == .extend(next))
    }

    @Test func aFingerThatJoinsAnExistingTouchNeverPaints() {
        var arbiter = PaintTouchArbiter()
        // The reported bug: brushing with a stray finger while two others pan.
        #expect(arbiter.touchDown(activeTouches: 2, at: .zero, time: 0) == .ignore)
        #expect(arbiter.touchMoved(to: CGPoint(x: 40, y: 40), time: 0.1) == .ignore)
    }

    @Test func multiTouchLatchesUntilEveryFingerIsOffThePhoto() {
        var arbiter = PaintTouchArbiter()
        _ = arbiter.touchDown(activeTouches: 2, at: .zero, time: 0)
        // A finger lifting and re-touching mid-pan is still not a stroke.
        #expect(arbiter.touchDown(activeTouches: 1, at: .zero, time: 0.2) == .ignore)
        arbiter.allFingersUp(time: 0.5)
        #expect(arbiter.touchDown(activeTouches: 1, at: .zero, time: 1) == .track(.zero))
    }

    @Test func theStragglerFingerOfAPanIsIgnoredUntilTheCooldownPasses() {
        var arbiter = PaintTouchArbiter()
        _ = arbiter.touchDown(activeTouches: 2, at: .zero, time: 0)
        arbiter.allFingersUp(time: 1)
        #expect(arbiter.touchDown(activeTouches: 1, at: .zero, time: 1.1) == .ignore)
        arbiter.allFingersUp(time: 1.15)
        #expect(arbiter.touchDown(activeTouches: 1, at: .zero, time: 1.5) == .track(.zero))
    }

    @Test func aLongStrokeSurvivesASecondFingerButAStubDoesNot() {
        var long = PaintTouchArbiter()
        _ = long.touchDown(activeTouches: 1, at: .zero, time: 0)
        _ = long.touchMoved(to: CGPoint(x: 20, y: 0), time: 0.1)
        #expect(long.extraFingerDown(time: 0.2) == .finish)

        var stub = PaintTouchArbiter()
        _ = stub.touchDown(activeTouches: 1, at: .zero, time: 0)
        // Confirmed by the delay rather than by distance: 3pt of travel is a
        // graze, not a stroke worth keeping.
        _ = stub.touchMoved(to: CGPoint(x: 3, y: 0), time: 0.1)
        #expect(stub.extraFingerDown(time: 0.2) == .discard)
    }

    @Test func aSystemCancelIsJudgedLikeASecondFinger() {
        var long = PaintTouchArbiter()
        _ = long.touchDown(activeTouches: 1, at: .zero, time: 0)
        _ = long.touchMoved(to: CGPoint(x: 30, y: 0), time: 0.1)
        #expect(long.systemCancelled() == .finish)

        var pending = PaintTouchArbiter()
        _ = pending.touchDown(activeTouches: 1, at: .zero, time: 0)
        #expect(pending.systemCancelled() == .ignore)
    }

    @Test func aRefusedTouchStaysRefusedForTheRestOfItsSequence() {
        var arbiter = PaintTouchArbiter()
        _ = arbiter.touchDown(activeTouches: 1, at: .zero, time: 0)
        _ = arbiter.touchMoved(to: CGPoint(x: 20, y: 0), time: 0.1)
        #expect(arbiter.extraFingerDown(time: 0.2) == .finish)
        // The finger still on the photo must not resume painting when the other
        // one leaves.
        #expect(arbiter.touchMoved(to: CGPoint(x: 40, y: 0), time: 0.3) == .ignore)
        #expect(arbiter.touchUp(time: 0.4) == .ignore)
    }
}
