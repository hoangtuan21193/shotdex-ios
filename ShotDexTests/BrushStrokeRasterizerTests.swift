import CoreGraphics
import Testing
@testable import ShotDex

@Suite struct BrushStrokeRasterizerTests {
    /// Coverage the passes add up to at the centre of the stamp, composited the way
    /// Core Graphics composites them: each pass over what the earlier ones left.
    private func coverage(_ rings: [BrushStrokeRasterizer.Ring]) -> Double {
        rings.reduce(0.0) { covered, ring in
            covered + (1 - covered) * Double(ring.alpha)
        }
    }

    @Test func theStampReachesFlowAtItsCoreAndFadesToNothingAtItsEdge() {
        let rings = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        #expect(rings.count > 1)
        #expect(abs(coverage(rings) - 0.8) < 0.0001)

        // Outermost pass first, shrinking to the hard core, and every pass is a
        // legal alpha.
        let widths = rings.map(\.lineWidth)
        #expect(widths == widths.sorted(by: >))
        #expect(rings.allSatisfy { $0.alpha >= 0 && $0.alpha <= 1 })

        // The widest pass is the full stamp — the outer ring `EditorBrushCursor`
        // draws — and the last one is the core it draws inside it.
        let full = EditorLayoutMetrics.brushDiameter(
            size: 0.25,
            in: CGRect(x: 0, y: 0, width: 1_600, height: 1_600)
        )
        let core = full * EditorLayoutMetrics.brushCoreScale(feather: 0.45)
        #expect(abs(widths.first! - full) < full / Double(rings.count))
        #expect(abs(widths.last! - core) < 0.0001)
    }

    @Test func aStrokePaintedZoomedInIsExactlyAsStrongAsOneAtFit() {
        // The regression this guards: the renderer used to blur the whole mask with
        // one radius taken from the *largest* stroke, so a stroke recorded at 500%
        // (a fifth of the width, because the Size slider is a screen size) was
        // smeared to nothing next to a stroke painted at 100%.
        let atFit = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        let zoomed = BrushStrokeRasterizer.rings(
            size: EditorLayoutMetrics.paintedSize(0.25, zoomScale: 5),
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )

        // Same strength — that is the whole point.
        #expect(abs(coverage(atFit) - coverage(zoomed)) < 0.0001)

        // And the same shape, only narrower. A thinner stamp has a thinner soft edge
        // so it is cut into fewer passes, which is why the two cannot be compared
        // pass for pass: what has to match is the *profile* both sample, so each is
        // checked against the same law — coverage `0.8 · smoothstep(t)` at a width
        // running from the full stamp down to the core.
        let core = EditorLayoutMetrics.brushCoreScale(feather: 0.45)
        for rings in [atFit, zoomed] {
            let full = rings[0].lineWidth / (1 - (1 - core) / Double(rings.count))
            var covered = 0.0
            for (index, ring) in rings.enumerated() {
                covered += (1 - covered) * Double(ring.alpha)
                let position = Double(index + 1) / Double(rings.count)
                let expected = 0.8 * position * position * (3 - 2 * position)
                #expect(abs(covered - expected) < 0.0001)
                #expect(
                    abs(ring.lineWidth / full - (1 - (1 - core) * position)) < 0.0001
                )
            }
        }

        // The zoomed stamp really is a fifth as wide — same ink, finer detail.
        #expect(abs(atFit.last!.lineWidth / zoomed.last!.lineWidth - 5) < 0.0001)
    }

    @Test func anEraserTakesThePixelAwayCompletelyAtItsCentre() {
        let rings = BrushStrokeRasterizer.rings(
            size: 0.2,
            feather: 0.5,
            flow: 0.3,
            isEraser: true,
            shortEdge: 1_600
        )
        // Flow shapes a paint stroke, not a removal: the core erases fully, the way
        // the `.clear` blend it replaced did.
        #expect(abs(coverage(rings) - 1) < 0.0001)
        #expect(rings.count > 1)
    }

    @Test func aHardBrushIsASinglePass() {
        let hard = BrushStrokeRasterizer.rings(
            size: 0.25,
            feather: 0,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_600
        )
        #expect(hard.count == 1)
        #expect(abs(hard[0].alpha - 0.8) < 0.0001)
        #expect(abs(hard[0].lineWidth - 400) < 0.0001)

        // A stamp whose soft edge is thinner than a pixel is not worth ramping, and
        // must still land at full strength rather than being rounded away.
        let tiny = BrushStrokeRasterizer.rings(
            size: 0.002,
            feather: 0.45,
            flow: 0.8,
            isEraser: false,
            shortEdge: 1_000
        )
        #expect(tiny.count == 1)
        #expect(abs(coverage(tiny) - 0.8) < 0.0001)
    }

    @Test func theRampNeverCostsMoreThanItsCap() {
        // A whole-frame brush must not turn into hundreds of path fills per render.
        let huge = BrushStrokeRasterizer.rings(
            size: 0.5,
            feather: 1,
            flow: 1,
            isEraser: false,
            shortEdge: 4_800
        )
        #expect(huge.count == BrushStrokeRasterizer.maximumRings)
        #expect(abs(coverage(huge) - 1) < 0.0001)
    }
}
