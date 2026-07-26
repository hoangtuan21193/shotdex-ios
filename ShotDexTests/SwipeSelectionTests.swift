import CoreGraphics
import Testing
@testable import ShotDex

struct SwipeSelectionTests {

    // MARK: Activation

    @Test func belowThresholdStaysUndecided() {
        let result = SwipeSelection.activation(translation: CGSize(width: 5, height: 5))
        #expect(result == .undecided)
    }

    @Test func horizontalDragActivatesSelect() {
        let result = SwipeSelection.activation(translation: CGSize(width: 12, height: 3))
        #expect(result == .select)
    }

    @Test func verticalDragActivatesScroll() {
        let result = SwipeSelection.activation(translation: CGSize(width: 3, height: -12))
        #expect(result == .scroll)
    }

    @Test func perfectDiagonalPrefersScroll() {
        let result = SwipeSelection.activation(translation: CGSize(width: 10, height: 10))
        #expect(result == .scroll)
    }

    @Test func leftwardDragAlsoSelects() {
        let result = SwipeSelection.activation(translation: CGSize(width: -12, height: 0))
        #expect(result == .select)
    }

    @Test func barelyHorizontalDiagonalStillScrolls() {
        let result = SwipeSelection.activation(translation: CGSize(width: 11, height: 10))
        #expect(result == .scroll)
    }

    // MARK: Edge auto-scroll

    private let visibleBounds = CGRect(x: 0, y: 100, width: 320, height: 600)

    @Test func middleOfViewportDoesNotAutoScroll() {
        #expect(
            SwipeSelection.autoScrollDelta(
                locationY: 400, visibleBounds: visibleBounds
            ) == 0
        )
    }

    @Test func topEdgeScrollsUpAndBottomEdgeScrollsDown() {
        #expect(
            SwipeSelection.autoScrollDelta(
                locationY: 100, visibleBounds: visibleBounds
            ) == -14
        )
        #expect(
            SwipeSelection.autoScrollDelta(
                locationY: 700, visibleBounds: visibleBounds
            ) == 14
        )
    }

    @Test func edgeAutoScrollAcceleratesTowardPhysicalEdge() {
        let inner = SwipeSelection.autoScrollDelta(
            locationY: 150, visibleBounds: visibleBounds
        )
        let outer = SwipeSelection.autoScrollDelta(
            locationY: 115, visibleBounds: visibleBounds
        )
        #expect(inner < 0)
        #expect(outer < inner)
    }
}
