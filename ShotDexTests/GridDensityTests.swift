import CoreGraphics
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

    /// The drawn count has its own, higher ceiling — a pinch cannot reach it,
    /// but a wide display resolves into it.
    @Test func clampedResolvedHasAHigherCeilingThanAPinch() {
        #expect(GridDensity.clampedResolved(12) == 12)
        #expect(GridDensity.clampedResolved(99) == GridDensity.resolvedColumnRange.upperBound)
        #expect(GridDensity.clampedResolved(0) == 1)
        #expect(GridDensity.resolvedColumnRange.upperBound > GridDensity.columnRange.upperBound)
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

    /// A regular-width display draws more columns than it was pinched to, and
    /// they are *tighter* than the compact tile, not merely proportional:
    /// scaling one-for-one left an iPad with a handful of huge thumbnails.
    @Test func regularWidthPacksMoreColumnsThanAProportionalScale() {
        // iPhone Duo unfolded, measured: 867pt of content at density 3.
        let duo = GridDensity.columns(forDensity: 3, width: 867, isRegularWidth: true)
        #expect(duo == 9)
        // Strictly denser than plain width-proportional scaling would give.
        #expect(CGFloat(duo) > 3 * 867 / GridDensity.compactReferenceWidth)

        // 11-inch iPad, portrait then landscape.
        #expect(GridDensity.columns(forDensity: 3, width: 834, isRegularWidth: true) == 9)
        #expect(GridDensity.columns(forDensity: 3, width: 1194, isRegularWidth: true) == 13)
    }

    /// Tiles stay roughly the same size across widths at a given density —
    /// wider screens buy more photos, not bigger ones.
    @Test func regularWidthKeepsTileSizeStableAcrossWidths() {
        let sizes = [700.0, 834.0, 1024.0, 1194.0, 1366.0].map { (width: CGFloat) in
            width / CGFloat(GridDensity.columns(forDensity: 3, width: width, isRegularWidth: true))
        }
        #expect(sizes.allSatisfy { $0 > 80 && $0 < 110 })
    }

    /// The sparsest pinch stays sparse: density 1 on an iPad is a few big
    /// tiles, not a dense contact sheet.
    @Test func regularWidthRespectsASparseDensity() {
        #expect(GridDensity.columns(forDensity: 1, width: 834, isRegularWidth: true) == 3)
        #expect(GridDensity.columns(forDensity: 2, width: 834, isRegularWidth: true) == 6)
    }

    @Test func regularWidthClampsToTheResolvedRange() {
        #expect(
            GridDensity.columns(forDensity: 8, width: 1366, isRegularWidth: true)
                == GridDensity.resolvedColumnRange.upperBound
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
        #expect(
            GridDensity.columns(forDensity: 99, width: 626, isRegularWidth: true)
                == GridDensity.clampedResolved(
                    Int((8 * 626 / (GridDensity.compactReferenceWidth
                        * GridDensity.regularTileScale)).rounded())
                )
        )
    }

    // MARK: granularity

    /// The zoom ladder the pinch walks: day, then month, then year. Year was
    /// added 2026-09-19 when the Library got its date sections back, so the
    /// densest levels no longer stop at month.
    @Test func granularityMapping() {
        #expect(GridDensity.granularity(forColumns: 1) == .day)
        #expect(GridDensity.granularity(forColumns: 3) == .day)
        #expect(GridDensity.granularity(forColumns: 4) == .month)
        #expect(GridDensity.granularity(forColumns: 6) == .month)
        #expect(GridDensity.granularity(forColumns: 7) == .year)
        #expect(GridDensity.granularity(forColumns: 8) == .year)
    }
}
