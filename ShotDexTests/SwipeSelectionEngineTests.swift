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

    // MARK: Range

    private let ids = ["a", "b", "c", "d", "e"]

    @Test func forwardRange() {
        #expect(SwipeSelectionEngine.rangeIds(orderedIds: ids, startId: "b", currentId: "d") == ["b", "c", "d"])
    }

    @Test func backwardRangeKeepsGridOrder() {
        #expect(SwipeSelectionEngine.rangeIds(orderedIds: ids, startId: "d", currentId: "b") == ["b", "c", "d"])
    }

    @Test func singleTileRange() {
        #expect(SwipeSelectionEngine.rangeIds(orderedIds: ids, startId: "c", currentId: "c") == ["c"])
    }

    @Test func unknownStartIdGivesEmptyRange() {
        #expect(SwipeSelectionEngine.rangeIds(orderedIds: ids, startId: "x", currentId: "c").isEmpty)
    }

    @Test func unknownCurrentIdGivesEmptyRange() {
        #expect(SwipeSelectionEngine.rangeIds(orderedIds: ids, startId: "a", currentId: "x").isEmpty)
    }

    // MARK: Hit test

    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 100),
        "b": CGRect(x: 102, y: 0, width: 100, height: 100),
    ]

    @Test func pointInsideTileHits() {
        #expect(SwipeSelectionEngine.tileId(at: CGPoint(x: 150, y: 50), frames: frames) == "b")
    }

    @Test func pointInGapMisses() {
        #expect(SwipeSelectionEngine.tileId(at: CGPoint(x: 101, y: 50), frames: frames) == nil)
    }

    @Test func pointOutsideAllFramesMisses() {
        #expect(SwipeSelectionEngine.tileId(at: CGPoint(x: 500, y: 500), frames: frames) == nil)
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
