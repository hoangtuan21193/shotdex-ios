import CoreGraphics
import Testing
@testable import ShotDex

struct SwipeSelectionEngineTests {

    // MARK: Activation

    @Test func belowThresholdStaysUndecided() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: 5, height: 5))
        #expect(result == .undecided)
    }

    @Test func horizontalDragActivatesSelect() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: 12, height: 3))
        #expect(result == .select)
    }

    @Test func verticalDragActivatesScroll() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: 3, height: -12))
        #expect(result == .scroll)
    }

    @Test func perfectDiagonalPrefersScroll() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: 10, height: 10))
        #expect(result == .scroll)
    }

    @Test func leftwardDragAlsoSelects() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: -12, height: 0))
        #expect(result == .select)
    }

    @Test func barelyHorizontalDiagonalStillScrolls() {
        let result = SwipeSelectionEngine.activation(translation: CGSize(width: 11, height: 10))
        #expect(result == .scroll)
    }

    // MARK: Edge auto-scroll

    private let visibleBounds = CGRect(x: 0, y: 100, width: 320, height: 600)

    @Test func middleOfViewportDoesNotAutoScroll() {
        #expect(
            SwipeSelectionEngine.autoScrollDelta(
                locationY: 400, visibleBounds: visibleBounds
            ) == 0
        )
    }

    @Test func topEdgeScrollsUpAndBottomEdgeScrollsDown() {
        #expect(
            SwipeSelectionEngine.autoScrollDelta(
                locationY: 100, visibleBounds: visibleBounds
            ) == -14
        )
        #expect(
            SwipeSelectionEngine.autoScrollDelta(
                locationY: 700, visibleBounds: visibleBounds
            ) == 14
        )
    }

    @Test func edgeAutoScrollAcceleratesTowardPhysicalEdge() {
        let inner = SwipeSelectionEngine.autoScrollDelta(
            locationY: 150, visibleBounds: visibleBounds
        )
        let outer = SwipeSelectionEngine.autoScrollDelta(
            locationY: 115, visibleBounds: visibleBounds
        )
        #expect(inner < 0)
        #expect(outer < inner)
    }
}
