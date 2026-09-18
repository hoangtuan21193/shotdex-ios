import Foundation
import Testing
@testable import ShotDex

struct TimelineLaneLayoutTests {
    private func item(_ start: Double, _ end: Double, _ id: UUID = UUID()) -> TimelineLaneLayout.Item {
        TimelineLaneLayout.Item(id: id, start: start, end: end)
    }

    @Test func emptyInputHasNoLanes() {
        let assignment = TimelineLaneLayout.assignLanes([])
        #expect(assignment.isEmpty)
        #expect(TimelineLaneLayout.laneCount(for: assignment) == 0)
    }

    @Test func disjointItemsShareTheFirstLane() {
        let items = [item(0, 2), item(3, 5), item(6, 9)]
        let assignment = TimelineLaneLayout.assignLanes(items)
        #expect(items.allSatisfy { assignment[$0.id] == 0 })
        #expect(TimelineLaneLayout.laneCount(for: assignment) == 1)
    }

    @Test func overlappingItemsStackIntoASecondLane() {
        let first = item(0, 5)
        let second = item(2, 7)
        let assignment = TimelineLaneLayout.assignLanes([first, second])
        #expect(assignment[first.id] == 0)
        #expect(assignment[second.id] == 1)
        #expect(TimelineLaneLayout.laneCount(for: assignment) == 2)
    }

    /// Touching windows are not an overlap — a caption that ends exactly where
    /// the next one starts stays on the same lane.
    @Test func touchingItemsShareALane() {
        let first = item(0, 4)
        let second = item(4, 8)
        let assignment = TimelineLaneLayout.assignLanes([first, second])
        #expect(assignment[first.id] == 0)
        #expect(assignment[second.id] == 0)
    }

    @Test func threeWayOverlapNeedsThreeLanes() {
        let items = [item(0, 9), item(1, 8), item(2, 7)]
        let assignment = TimelineLaneLayout.assignLanes(items)
        #expect(TimelineLaneLayout.laneCount(for: assignment) == 3)
        #expect(Set(items.compactMap { assignment[$0.id] }) == [0, 1, 2])
    }

    /// A freed lane is reused before a new one is opened.
    @Test func alaneIsReusedOnceItsOccupantEnds() {
        let long = item(0, 10)
        let early = item(0, 3)
        let late = item(4, 6)
        let assignment = TimelineLaneLayout.assignLanes([long, early, late])
        #expect(TimelineLaneLayout.laneCount(for: assignment) == 2)
        #expect(assignment[early.id] == assignment[late.id])
    }

    /// Same items, different input order → same lanes. Lanes must not shuffle
    /// just because the recipe's array order changed.
    @Test func assignmentIsIndependentOfInputOrder() {
        let items = [item(0, 5), item(2, 7), item(4, 9), item(8, 12)]
        let forward = TimelineLaneLayout.assignLanes(items)
        let reversed = TimelineLaneLayout.assignLanes(items.reversed())
        #expect(forward == reversed)
    }

    /// Ties on both start and end fall back to the id, so equal windows still
    /// land deterministically.
    @Test func identicalWindowsAreOrderedByID() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let assignment = TimelineLaneLayout.assignLanes([item(1, 4, high), item(1, 4, low)])
        #expect(assignment[low] == 0)
        #expect(assignment[high] == 1)
    }

    /// A zero-length window still occupies a lane slot without inverting.
    @Test func degenerateWindowsDoNotCrash() {
        let point = item(3, 3)
        let assignment = TimelineLaneLayout.assignLanes([point])
        #expect(assignment[point.id] == 0)
    }
}
