import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct OverlayAnimationMathTests {
    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: - Easing

    @Test func easingHitsEndpoints() {
        #expect(isClose(OverlayAnimationMath.easeOut(0), 0))
        #expect(isClose(OverlayAnimationMath.easeOut(1), 1))
        #expect(isClose(OverlayAnimationMath.easeIn(0), 0))
        #expect(isClose(OverlayAnimationMath.easeIn(1), 1))
    }

    @Test func easingClampsOutOfRange() {
        #expect(isClose(OverlayAnimationMath.easeOut(-1), 0))
        #expect(isClose(OverlayAnimationMath.easeIn(2), 1))
    }

    // MARK: - Enter poses

    @Test func noneIsAlwaysIdentity() {
        #expect(OverlayAnimationMath.enter(.none, progress: 0) == .identity)
        #expect(OverlayAnimationMath.enter(.none, progress: 0.5) == .identity)
        #expect(OverlayAnimationMath.exit(.none, progress: 1) == .identity)
    }

    @Test func fadeEntersFromTransparentToOpaque() {
        #expect(isClose(OverlayAnimationMath.enter(.fade, progress: 0).opacity, 0))
        #expect(isClose(OverlayAnimationMath.enter(.fade, progress: 1).opacity, 1))
    }

    @Test func slideUpStartsBelowAndSettles() {
        let start = OverlayAnimationMath.enter(.slideUp, progress: 0)
        // Screen-down positive: it begins one offset below its resting place.
        #expect(isClose(start.translation.height, OverlayAnimationMath.slideOffset))
        #expect(isClose(start.opacity, 0))
        let settled = OverlayAnimationMath.enter(.slideUp, progress: 1)
        #expect(settled == .identity)
    }

    @Test func slideDirectionsHaveOppositeSigns() {
        let up = OverlayAnimationMath.enter(.slideUp, progress: 0).translation
        let down = OverlayAnimationMath.enter(.slideDown, progress: 0).translation
        let left = OverlayAnimationMath.enter(.slideLeft, progress: 0).translation
        let right = OverlayAnimationMath.enter(.slideRight, progress: 0).translation
        #expect(isClose(up.height, -down.height))
        #expect(isClose(left.width, -right.width))
    }

    @Test func popEntersSmallAndGrowsToFull() {
        let start = OverlayAnimationMath.enter(.pop, progress: 0)
        #expect(isClose(start.scale, OverlayAnimationMath.popScale))
        let settled = OverlayAnimationMath.enter(.pop, progress: 1)
        #expect(isClose(settled.scale, 1))
    }

    // MARK: - Exit poses

    @Test func fadeExitsFromOpaqueToTransparent() {
        #expect(isClose(OverlayAnimationMath.exit(.fade, progress: 0).opacity, 1))
        #expect(isClose(OverlayAnimationMath.exit(.fade, progress: 1).opacity, 0))
    }

    @Test func slideUpExitsUpward() {
        let gone = OverlayAnimationMath.exit(.slideUp, progress: 1)
        // Screen-up is negative: it leaves above its resting place.
        #expect(isClose(gone.translation.height, -OverlayAnimationMath.slideOffset))
        #expect(isClose(gone.opacity, 0))
    }

    // MARK: - Combine

    @Test func combineWithIdentityIsUnchanged() {
        let pose = OverlayAnimationMath.Transform(
            opacity: 0.5, translation: CGSize(width: 0.1, height: -0.2), scale: 0.8
        )
        #expect(pose.combined(with: .identity) == pose)
        #expect(OverlayAnimationMath.Transform.identity.combined(with: pose) == pose)
    }

    // MARK: - TimedOverlay windows

    private func timed(
        animateIn: OverlayAnimation = .none,
        animateOut: OverlayAnimation = .none,
        start: Double = 0,
        duration: Double? = 2
    ) -> TimedOverlay {
        TimedOverlay(
            overlay: .text(),
            start: start,
            duration: duration,
            animateIn: animateIn,
            animateOut: animateOut,
            inDuration: 0.4,
            outDuration: 0.4
        )
    }

    @Test func fadeInRampsThenSettles() {
        let overlay = timed(animateIn: .fade)
        #expect(isClose(overlay.animationTransform(at: 0, total: 2).opacity, 0))
        // Fully past the 0.4s in-ramp: identity.
        #expect(overlay.animationTransform(at: 1.0, total: 2) == .identity)
    }

    @Test func fadeOutRampsBeforeTheEnd() {
        let overlay = timed(animateOut: .fade)   // window 0…2, out ramp 1.6…2.0
        #expect(overlay.animationTransform(at: 1.0, total: 2) == .identity)
        #expect(isClose(overlay.animationTransform(at: 1.6, total: 2).opacity, 1))
        #expect(overlay.animationTransform(at: 1.99, total: 2).opacity < 0.1)
    }

    @Test func rampClampsToShortWindow() {
        // Window is only 0.2s but the in-ramp default is 0.4s: it clamps so the
        // caption is still fully faded in by the end of its window.
        let overlay = timed(animateIn: .fade, duration: 0.2)
        #expect(isClose(overlay.animationTransform(at: 0, total: 5).opacity, 0))
        #expect(overlay.animationTransform(at: 0.19, total: 5).opacity > 0.5)
    }

    @Test func openEndedOverlayUsesTotalForOut() {
        // duration nil → visible until the total; the out ramp hangs off the total.
        let overlay = timed(animateOut: .fade, duration: nil)
        #expect(isClose(overlay.animationTransform(at: 2.0, total: 5).opacity, 1))
        #expect(overlay.animationTransform(at: 4.9, total: 5).opacity < 0.2)
    }
}
