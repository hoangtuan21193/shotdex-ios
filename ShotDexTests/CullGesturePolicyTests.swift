import Testing
@testable import ShotDex

/// FS-01.12b AC-2 — swipes flag at fit and never while zoomed.
struct CullGesturePolicyTests {

    @Test func atFitSwipesFlagAndPage() {
        #expect(CullGesturePolicy.action(for: .up, zoomScale: 1) == .flag(.pick))
        #expect(CullGesturePolicy.action(for: .down, zoomScale: 1) == .flag(.reject))
        #expect(CullGesturePolicy.action(for: .left, zoomScale: 1) == .next)
        #expect(CullGesturePolicy.action(for: .right, zoomScale: 1.005) == .previous)
    }

    /// At 2× a downward drag moves the photo: no flag, no page turn.
    @Test func zoomedSwipesDoNothing() {
        for swipe in [CullGesturePolicy.Swipe.up, .down, .left, .right] {
            #expect(CullGesturePolicy.action(for: swipe, zoomScale: 2) == nil)
        }
    }
}
