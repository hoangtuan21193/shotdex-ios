import CoreGraphics
import Foundation

/// Draws mask brush strokes into a grayscale context, giving each stroke its own
/// soft edge.
///
/// The renderers used to stroke every path hard and then run **one** Gaussian blur
/// over the finished mask, with a radius taken from the *largest* stroke in the
/// component (`feather × maxSize × shortEdge × 0.45`). That is fine while every
/// stroke is the same size and wrong the moment they are not — and zoom is exactly
/// what makes them differ, because the Size slider is a screen size so a stroke
/// painted at 500% records a fifth of the width. A thin stroke blurred by a radius
/// derived from a fat one is smeared over several times its own width, and its peak
/// alpha collapses: paint at 100%, zoom in, paint again, and the second stroke comes
/// out barely visible — or vanishes entirely the moment a bigger stroke is added
/// next to it. That is the bug this replaces.
///
/// So the feather is rasterized per stroke instead, as concentric passes from the
/// full stamp inwards to the hard core, each adding a little more alpha. No blur, no
/// coupling between strokes, and the same profile at every size — which is what makes
/// a stroke painted at 800% read exactly as strongly as one painted at 100%.
///
/// It also makes the stamp honest: it now ends at the full width, which is the outer
/// ring `EditorBrushCursor` draws. The old Gaussian spilled past that ring.
enum BrushStrokeRasterizer {
    /// One concentric pass: how wide to stroke, and the alpha to stroke it with so
    /// that the passes so far add up to the intended coverage.
    struct Ring: Equatable {
        var lineWidth: CGFloat
        /// Source alpha for *this* pass, not the cumulative coverage — the passes
        /// composite over each other, so each one only has to close the gap.
        var alpha: CGFloat
    }

    /// Widest a soft edge is allowed to be cut into. Enough that the banding is
    /// finer than the mask is ever resampled to, cheap enough that a mask of thirty
    /// strokes is still a handful of path fills.
    static let maximumRings = 20

    /// The passes that make up one stroke, outermost first.
    ///
    /// Every alpha here is a pure function of `feather`, `flow` and `isEraser` — the
    /// size only scales the widths. Two strokes with the same settings painted at
    /// different zooms therefore land at the same strength, differing only in how
    /// much of the photo they cover.
    static func rings(
        size: Double,
        feather: Double,
        flow: Double,
        isEraser: Bool,
        shortEdge: CGFloat
    ) -> [Ring] {
        let full = max(1, CGFloat(size) * shortEdge)
        let core = full * EditorLayoutMetrics.brushCoreScale(feather: feather)
        // An eraser takes the pixel away completely at its centre, the way the old
        // `.clear` blend did; flow shapes a paint stroke, not a removal.
        let peak = isEraser ? 1 : min(1, max(0.01, flow))
        let ramp = (full - core) / 2

        // No feather, or a stamp so small the ramp is sub-pixel: one hard pass.
        guard ramp > 0.5 else {
            return [Ring(lineWidth: full, alpha: CGFloat(peak))]
        }

        let steps = min(Self.maximumRings, max(3, Int(ramp / 2)))
        var rings: [Ring] = []
        rings.reserveCapacity(steps)
        var covered = 0.0
        for step in 1...steps {
            let position = Double(step) / Double(steps)
            // Smoothstep rather than a straight line: a linear ramp leaves a visible
            // crease where the soft edge meets the core, which a Gaussian never had.
            let target = peak * position * position * (3 - 2 * position)
            // Source-over, so this pass only has to cover the shortfall.
            let alpha = covered >= 1 ? 1 : (target - covered) / (1 - covered)
            covered = target
            rings.append(
                Ring(
                    lineWidth: full - (full - core) * CGFloat(position),
                    alpha: CGFloat(min(1, max(0, alpha)))
                )
            )
        }
        return rings
    }

    /// Strokes `strokes` into `context` in order. `point` maps a normalized mask
    /// coordinate into the context's own pixels — the two renderers flip y through
    /// their own `imagePoint`, so neither the flip nor the extent offset lives here.
    static func draw(
        _ strokes: [BrushStroke],
        in context: CGContext,
        shortEdge: CGFloat,
        point: (NormalizedPoint) -> CGPoint
    ) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // Erasers paint black rather than clearing: a hard `.clear` cannot take a
        // partial bite, so a feathered eraser had no soft edge of its own either.
        context.setBlendMode(.normal)

        for stroke in strokes where !stroke.points.isEmpty {
            let gray: CGFloat = stroke.isEraser ? 0 : 1
            let passes = rings(
                size: stroke.size,
                feather: stroke.feather,
                flow: stroke.flow,
                isEraser: stroke.isEraser,
                shortEdge: shortEdge
            )
            let mapped = stroke.points.map(point)
            for ring in passes {
                context.setStrokeColor(gray: gray, alpha: ring.alpha)
                context.setLineWidth(ring.lineWidth)
                context.beginPath()
                context.move(to: mapped[0])
                for next in mapped.dropFirst() {
                    context.addLine(to: next)
                }
                if mapped.count == 1 {
                    // A tap has to leave a dot, and a path with one point strokes
                    // nothing.
                    context.addLine(to: mapped[0])
                }
                context.strokePath()
            }
        }
    }
}
