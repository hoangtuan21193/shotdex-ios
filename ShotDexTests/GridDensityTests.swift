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

    // MARK: columns(forDensity:width:isRegularWidth:)

    /// Every shipping iPhone is horizontally compact, so the stored density is
    /// what gets drawn — including on the widest (Max) and narrowest (SE)
    /// screens, and on iPhone Duo's compact-width outer display.
    @Test func compactWidthDrawsTheStoredDensity() {
        for width in [320.0, 375.0, 393.0, 430.0, 466.0] as [CGFloat] {
            for density in GridDensity.columnRange {
                #expect(
                    GridDensity.columns(
                        forDensity: density, width: width, isRegularWidth: false
                    ) == density
                )
            }
        }
    }

    /// iPhone Duo's inner display: 626pt and regular width. The count grows
    /// with the width so the tile size survives unfolding (626/5 ≈ 393/3).
    @Test func regularWidthScalesColumnsWithWidth() {
        #expect(GridDensity.columns(forDensity: 3, width: 626, isRegularWidth: true) == 5)
        #expect(GridDensity.columns(forDensity: 1, width: 626, isRegularWidth: true) == 2)
        #expect(GridDensity.columns(forDensity: 4, width: 626, isRegularWidth: true) == 6)
    }

    @Test func regularWidthClampsToTheSupportedRange() {
        #expect(
            GridDensity.columns(forDensity: 8, width: 626, isRegularWidth: true)
                == GridDensity.columnRange.upperBound
        )
    }

    /// A regular-width window narrower than the reference (Split View on the
    /// inner display) must not shrink the grid below the stored density.
    @Test func regularWidthNarrowerThanReferenceIsUntouched() {
        #expect(GridDensity.columns(forDensity: 3, width: 320, isRegularWidth: true) == 3)
        #expect(GridDensity.columns(forDensity: 3, width: 393, isRegularWidth: true) == 3)
    }

    @Test func columnsSanitizeStoredGarbage() {
        #expect(GridDensity.columns(forDensity: 0, width: 393, isRegularWidth: false) == 1)
        #expect(GridDensity.columns(forDensity: 99, width: 626, isRegularWidth: true) == 8)
    }

    // MARK: granularity

    @Test func granularityMapping() {
        #expect(GridDensity.granularity(forColumns: 1) == .day)
        #expect(GridDensity.granularity(forColumns: 3) == .day)
        #expect(GridDensity.granularity(forColumns: 4) == .month)
        #expect(GridDensity.granularity(forColumns: 8) == .month)
    }
}
