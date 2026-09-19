import CoreGraphics

/// How the compare screen's cards are laid out across the width it is given.
///
/// One column on a phone, two or three on an iPad or the Duo's inner display.
/// The rule is the wide-screen rule the rest of the app follows: a wider screen
/// earns *more* cards, not bigger ones — a single card blown up to 1000pt is
/// one photo where three would fit, and comparing is the whole point of the
/// screen.
///
/// Pure and tested (`CompareLayoutTests`) because the interesting cases are the
/// ones that are awkward to reach by hand: the Duo's 466pt cover, an iPad in
/// portrait, and two photos on a display with room for three.
enum CompareLayout {

    /// The narrowest a card may be before the frame inside it stops being worth
    /// judging. Below this the screen takes a column away.
    static let minimumCardWidth: CGFloat = 330

    /// More than three cards across and each one is too small to tell two
    /// exposures apart, however much width there is.
    static let maximumColumns = 3

    /// Columns for `count` cards across `width` points of usable canvas.
    ///
    /// Capped by the number of photos: two photos on a 13" iPad are two columns
    /// and a gap, not three columns with a hole in the third.
    static func columns(count: Int, width: CGFloat, spacing: CGFloat) -> Int {
        guard count > 0, width > 0 else { return 1 }
        // Solve for the largest n where each of n cards still clears the
        // minimum once the gaps between them are paid for.
        var fitting = 1
        for candidate in 2...maximumColumns {
            let gaps = spacing * CGFloat(candidate - 1)
            let cardWidth = (width - gaps) / CGFloat(candidate)
            if cardWidth >= minimumCardWidth { fitting = candidate }
        }
        return min(fitting, count)
    }

    /// Splits card indices into `columns` columns, keeping each column's total
    /// height close to the others'.
    ///
    /// Cards are as tall as their photo is, so dealing them out round-robin
    /// leaves one column running far past the rest — three portrait frames in
    /// column one against three landscape in column two. Each card goes to the
    /// column that is shortest so far, which keeps the bottom edge roughly
    /// level and preserves selection order down each column.
    ///
    /// `aspectRatios` are width ÷ height; a card's height is proportional to
    /// the inverse, so that is what accumulates.
    static func distribute(aspectRatios: [CGFloat], columns: Int) -> [[Int]] {
        let columnCount = max(1, columns)
        guard columnCount > 1 else { return [Array(aspectRatios.indices)] }

        var buckets: [[Int]] = Array(repeating: [], count: columnCount)
        var heights = [CGFloat](repeating: 0, count: columnCount)

        for (index, ratio) in aspectRatios.enumerated() {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            buckets[shortest].append(index)
            // A zero or negative ratio is a missing asset; treat it as square
            // rather than letting it poison the running totals.
            heights[shortest] += ratio > 0 ? 1 / ratio : 1
        }
        return buckets
    }
}
