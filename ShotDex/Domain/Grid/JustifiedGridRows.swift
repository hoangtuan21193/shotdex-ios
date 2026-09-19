import CoreGraphics

/// One row of a justified grid: which photos are in it and how tall it is.
struct JustifiedRow: Equatable, Sendable {
    /// Flat indices into the array of aspect ratios this row was built from.
    var range: Range<Int>
    var height: CGFloat
}

/// The photo-shaped grid — Photos' aspect-ratio toggle.
///
/// Every row fills the width exactly and every photo in it keeps its own
/// shape, so the row's height is whatever makes that true: a row of wide
/// frames is short, a row of portraits is tall. This is the arrangement a
/// contact sheet has had since contact sheets were paper, and the reason it is
/// worth the bookkeeping is that a square crop hides how the photo was framed
/// — which is the one thing a photographer is looking for on this screen.
///
/// Pure, so the arithmetic is unit-tested without a collection view: the layout
/// only turns these rows into frames.
enum JustifiedGridRows {

    /// A single frame is never allowed to be wider than this many times its
    /// height, or narrower than the reciprocal.
    ///
    /// Without it one panorama at 8:1 becomes a row of its own 40pt tall, and
    /// a scan at 1:5 pushes a row past the height of the screen. Photos crops
    /// both; this keeps the frame and only stops the *row* from following it
    /// all the way.
    static let aspectClamp: ClosedRange<CGFloat> = (1.0 / 3.0)...3.0

    /// Groups `aspectRatios` (width ÷ height) into rows that each fill
    /// `width`, aiming for rows about `targetHeight` tall.
    ///
    /// The target is what the column count means in this mode: at six columns
    /// the square grid's cell side is the height the rows aim for, so pinching
    /// still changes how much of the library is on screen.
    static func rows(
        aspectRatios: [CGFloat],
        width: CGFloat,
        targetHeight: CGFloat,
        spacing: CGFloat
    ) -> [JustifiedRow] {
        guard !aspectRatios.isEmpty, width > 0, targetHeight > 0 else { return [] }

        var rows: [JustifiedRow] = []
        var start = 0
        var aspectSum: CGFloat = 0

        for index in aspectRatios.indices {
            aspectSum += clamped(aspectRatios[index])
            let count = index - start + 1
            let available = width - spacing * CGFloat(count - 1)
            guard available > 0 else { continue }
            let height = available / aspectSum
            // The row is closed the moment one more frame would make it
            // shorter than asked for: adding the next photo only ever lowers
            // the row, so this is the last point at which it is still at least
            // the target.
            if height <= targetHeight {
                rows.append(JustifiedRow(range: start..<(index + 1), height: height))
                start = index + 1
                aspectSum = 0
            }
        }

        if start < aspectRatios.count {
            // The last row is short of photos, so filling the width would
            // blow it up — two landscapes stretched to 1032pt would tower over
            // the rows above. It keeps the target height and simply ends early.
            let count = aspectRatios.count - start
            let available = width - spacing * CGFloat(count - 1)
            let natural = available / aspectSum
            rows.append(
                JustifiedRow(range: start..<aspectRatios.count, height: min(natural, targetHeight))
            )
        }
        return rows
    }

    /// The width one frame takes in a row of the given height.
    static func itemWidth(aspectRatio: CGFloat, rowHeight: CGFloat) -> CGFloat {
        max(1, clamped(aspectRatio) * rowHeight)
    }

    /// Total height of a stack of rows, gaps included.
    static func totalHeight(_ rows: [JustifiedRow], spacing: CGFloat) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(rows.count - 1)
    }

    static func clamped(_ aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio > 0, aspectRatio.isFinite else { return 1 }
        return min(max(aspectRatio, aspectClamp.lowerBound), aspectClamp.upperBound)
    }
}
