import Foundation
import Testing
@testable import ShotDex

struct GridDensityTests {

    // MARK: clamped

    @Test func clampedSanitizesStoredValues() {
        #expect(GridDensity.clamped(1) == 1)
        #expect(GridDensity.clamped(3) == 3)
        #expect(GridDensity.clamped(8) == 8)
        // Out of range in both directions.
        #expect(GridDensity.clamped(0) == GridDensity.columnRange.lowerBound)
        #expect(GridDensity.clamped(-5) == GridDensity.columnRange.lowerBound)
        #expect(GridDensity.clamped(99) == GridDensity.columnRange.upperBound)
        // Legacy 9-column value clamps into the new range.
        #expect(GridDensity.clamped(9) == 8)
    }

    // MARK: stepped

    @Test func steppedMovesOneColumnPerStep() {
        #expect(GridDensity.stepped(3, by: 1) == 4)
        #expect(GridDensity.stepped(3, by: -1) == 2)
    }

    @Test func steppedClampsAtEnds() {
        #expect(GridDensity.stepped(GridDensity.columnRange.lowerBound, by: -1)
            == GridDensity.columnRange.lowerBound)
        #expect(GridDensity.stepped(GridDensity.columnRange.upperBound, by: 1)
            == GridDensity.columnRange.upperBound)
    }

    // MARK: granularity

    @Test func granularityMapping() {
        #expect(GridDensity.granularity(forColumns: 1) == .day)
        #expect(GridDensity.granularity(forColumns: 3) == .day)
        #expect(GridDensity.granularity(forColumns: 4) == .month)
        #expect(GridDensity.granularity(forColumns: 8) == .month)
    }
}
