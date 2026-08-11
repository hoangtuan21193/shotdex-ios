import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct CollageLayoutTests {
    // MARK: - Tiling invariants

    /// Every template's leaf count equals its declared cell count.
    @Test func leafCountMatchesCells() {
        for template in CollageTemplateCatalog.all {
            #expect(template.root.leafCount == template.cellCount, template.id)
            #expect(template.cells.count == template.cellCount, template.id)
        }
    }

    /// Resolving a skewed override still tiles the unit square exactly — the
    /// gutter math depends on it whatever the user drags a seam to.
    @Test func resolveWithOverrideStillTiles() {
        let cases: [(id: String, node: String, weights: [Double])] = [
            ("2-cols", "0", [3, 1]),
            ("4-grid", "0", [2, 1]),
            ("3-left-tall", "0", [3, 1]),
            ("9-4-1-4", "0", [1, 3, 1]),
        ]
        for test in cases {
            let template = CollageTemplateCatalog.template(id: test.id)!
            let cells = template.resolvedCells(overrides: [test.node: test.weights])
            #expect(cells.count == template.cellCount, test.id)
            assertTiles(cells, id: test.id)
        }
    }

    /// A skewed root override moves the seam proportionally.
    @Test func overrideChangesProportion() {
        let template = CollageTemplateCatalog.template(id: "2-cols")!
        let cells = template.resolvedCells(overrides: ["0": [3, 1]])
        #expect(abs(cells[0].width - 0.75) < 1e-9)
        #expect(abs(cells[1].width - 0.25) < 1e-9)
        #expect(abs(cells[1].x - 0.75) < 1e-9)
    }

    /// An override whose arity does not match the node (a leftover from another
    /// template) is ignored — the layout falls back to the default weights.
    @Test func staleOverrideIsIgnored() {
        let template = CollageTemplateCatalog.template(id: "2-cols")!
        let withStale = template.resolvedCells(overrides: ["0": [1, 1, 1]])
        #expect(withStale == template.cells)
    }

    // MARK: - Dividers

    /// Every divider names a split whose weights it can index into.
    @Test func dividersReferenceValidSplits() {
        for template in CollageTemplateCatalog.all {
            let dividers = template.dividers(overrides: [:])
            for divider in dividers {
                #expect(divider.weights.count >= 2, template.id)
                #expect(divider.index >= 0 && divider.index < divider.weights.count - 1, template.id)
                #expect(divider.nodeSpan > 0, template.id)
                #expect(divider.crossEnd > divider.crossStart, template.id)
            }
        }
    }

    /// A grid exposes one seam per interior boundary: the row split plus one per
    /// column split (2×2 → 1 + 2 = 3).
    @Test func gridDividerCount() {
        let template = CollageTemplateCatalog.template(id: "4-grid")!
        #expect(template.dividers(overrides: [:]).count == 3)
    }

    // MARK: - Divider math

    @Test func adjustedWeightsPreservesTotalAndOthers() {
        let weights: [Double] = [2, 1, 1]
        let result = CollageDividerMath.adjustedWeights(weights, boundary: 1, toFraction: 0.72, snap: false)
        #expect(abs(result.reduce(0, +) - 4) < 1e-9)      // total preserved
        #expect(abs(result[0] - 2) < 1e-9)                // untouched child fixed
    }

    @Test func adjustedWeightsRespectsFloor() {
        // Drag hard to one side; both children must keep ≥ 15% of the span.
        let result = CollageDividerMath.adjustedWeights([1, 1], boundary: 0, toFraction: 0.99, snap: false)
        let total = result.reduce(0, +)
        #expect(result[0] / total >= CollageDividerMath.minFraction - 1e-9)
        #expect(result[1] / total >= CollageDividerMath.minFraction - 1e-9)
        #expect(abs((result[0] / total) - (1 - CollageDividerMath.minFraction)) < 1e-9)
    }

    @Test func adjustedWeightsSoftSnaps() {
        // Near the halfway mark it snaps exactly onto it.
        let result = CollageDividerMath.adjustedWeights([1, 1], boundary: 0, toFraction: 0.515, snap: true)
        #expect(abs(result[0] - result[1]) < 1e-9)
    }

    @Test func adjustedWeightsIgnoresBadBoundary() {
        let weights: [Double] = [1, 1]
        #expect(CollageDividerMath.adjustedWeights(weights, boundary: 5, toFraction: 0.5, snap: false) == weights)
    }

    // MARK: - Helpers

    private func assertTiles(_ cells: [NormalizedRect], id: String) {
        let epsilon = 1e-6
        var area = 0.0
        for cell in cells {
            #expect(cell.x >= -epsilon && cell.y >= -epsilon, id)
            #expect(cell.x + cell.width <= 1 + epsilon, id)
            #expect(cell.y + cell.height <= 1 + epsilon, id)
            #expect(cell.width > epsilon && cell.height > epsilon, id)
            area += cell.width * cell.height
        }
        #expect(abs(area - 1) < 1e-4, "\(id) area \(area)")
        for i in 0..<cells.count {
            for j in (i + 1)..<cells.count {
                let overlap = cells[i].cgRect.intersection(cells[j].cgRect)
                let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
                #expect(overlapArea < 1e-4, "\(id) cells \(i)/\(j) overlap")
            }
        }
    }
}
