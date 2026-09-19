import CoreGraphics
import Testing
@testable import ShotDex

/// The photo-shaped grid's arithmetic: every row fills the width, every frame
/// keeps its shape, and the row height is whatever makes both true.
struct JustifiedGridRowsTests {

    private let width: CGFloat = 390
    private let spacing: CGFloat = 2

    /// A row is only closed once it has dropped to the target height, so each
    /// full row fills the width exactly.
    @Test func everyFullRowFillsTheWidth() {
        let aspects: [CGFloat] = (0..<40).map { $0.isMultiple(of: 3) ? 1.5 : 0.75 }
        let rows = JustifiedGridRows.rows(
            aspectRatios: aspects, width: width, targetHeight: 120, spacing: spacing
        )
        #expect(rows.count > 1)
        for row in rows.dropLast() {
            let used = row.range.reduce(CGFloat(0)) { sum, index in
                sum + JustifiedGridRows.itemWidth(aspectRatio: aspects[index], rowHeight: row.height)
            } + spacing * CGFloat(row.range.count - 1)
            #expect(abs(used - width) < 0.5, "row \(row.range) used \(used)")
        }
    }

    @Test func everyPhotoLandsInExactlyOneRow() {
        let aspects: [CGFloat] = (0..<37).map { _ in 1.4 }
        let rows = JustifiedGridRows.rows(
            aspectRatios: aspects, width: width, targetHeight: 100, spacing: spacing
        )
        #expect(rows.first?.range.lowerBound == 0)
        #expect(rows.last?.range.upperBound == aspects.count)
        for (a, b) in zip(rows, rows.dropFirst()) {
            #expect(a.range.upperBound == b.range.lowerBound)
        }
    }

    /// Wide frames eat the width quickly, so a landscape row holds fewer of
    /// them and comes out short; portraits pack in and stand tall. That
    /// difference is the whole point of the mode.
    @Test func landscapeRowsAreShorterAndHoldFewerFrames() {
        let landscape = JustifiedGridRows.rows(
            aspectRatios: Array(repeating: 1.5, count: 30),
            width: width, targetHeight: 120, spacing: spacing
        )
        let portrait = JustifiedGridRows.rows(
            aspectRatios: Array(repeating: 0.67, count: 30),
            width: width, targetHeight: 120, spacing: spacing
        )
        #expect(landscape[0].range.count < portrait[0].range.count)
        #expect(landscape[0].height < portrait[0].height)
    }

    /// The target is what the pinch controls, so a smaller target has to mean
    /// more photos on screen: more frames per row, and the whole stack
    /// shorter.
    @Test func aSmallerTargetPacksMorePhotosPerRow() {
        let aspects = Array(repeating: CGFloat(1.5), count: 60)
        let big = JustifiedGridRows.rows(
            aspectRatios: aspects, width: width, targetHeight: 180, spacing: spacing
        )
        let small = JustifiedGridRows.rows(
            aspectRatios: aspects, width: width, targetHeight: 60, spacing: spacing
        )
        #expect(small[0].range.count > big[0].range.count)
        #expect(
            JustifiedGridRows.totalHeight(small, spacing: spacing)
                < JustifiedGridRows.totalHeight(big, spacing: spacing)
        )
    }

    /// The last row is usually short of photos. Filling the width would tower
    /// over the rows above it, so it keeps the target height instead.
    @Test func aShortLastRowKeepsTheTargetHeightRatherThanStretching() {
        let rows = JustifiedGridRows.rows(
            aspectRatios: [1.5, 1.5], width: width, targetHeight: 100, spacing: spacing
        )
        #expect(rows.count == 1)
        #expect(rows[0].height <= 100.001)
    }

    /// A panorama must not turn into a 40pt sliver of a row, and a tall scan
    /// must not push one past the screen.
    @Test func extremeShapesAreClampedForLayoutButNotRefused() {
        let rows = JustifiedGridRows.rows(
            aspectRatios: [8, 0.2], width: width, targetHeight: 120, spacing: spacing
        )
        #expect(rows.count >= 1)
        for row in rows {
            #expect(row.height > 40)
            #expect(row.height <= 400)
        }
        #expect(JustifiedGridRows.clamped(8) == JustifiedGridRows.aspectClamp.upperBound)
        #expect(JustifiedGridRows.clamped(0.2) == JustifiedGridRows.aspectClamp.lowerBound)
    }

    /// A missing or nonsense ratio is a square, not a crash or a zero-width
    /// frame — grid rows load before the index has measured every photo.
    @Test func unknownShapesFallBackToSquare() {
        #expect(JustifiedGridRows.clamped(0) == 1)
        #expect(JustifiedGridRows.clamped(-3) == 1)
        #expect(JustifiedGridRows.clamped(.nan) == 1)
        // Infinity is not a very wide photo, it is a broken number.
        #expect(JustifiedGridRows.clamped(.infinity) == 1)
    }

    @Test func degenerateInputsProduceNoRows() {
        #expect(JustifiedGridRows.rows(aspectRatios: [], width: 390, targetHeight: 100, spacing: 2).isEmpty)
        #expect(JustifiedGridRows.rows(aspectRatios: [1.5], width: 0, targetHeight: 100, spacing: 2).isEmpty)
        #expect(JustifiedGridRows.rows(aspectRatios: [1.5], width: 390, targetHeight: 0, spacing: 2).isEmpty)
    }

    @Test func totalHeightCountsTheGapsBetweenRows() {
        let rows = [
            JustifiedRow(range: 0..<3, height: 100),
            JustifiedRow(range: 3..<6, height: 80),
        ]
        #expect(JustifiedGridRows.totalHeight(rows, spacing: 2) == 182)
        #expect(JustifiedGridRows.totalHeight([], spacing: 2) == 0)
    }
}
