import CoreGraphics

/// How many columns a survey puts its photos in — Lightroom's Survey view,
/// where the whole selection is on screen at once and nothing scrolls.
///
/// The rule is the same one `EditorLayoutMetrics.referenceSplit` uses for the
/// reference pane, generalised past two frames: try every column count and keep
/// whichever fits the biggest tile. Rows of photos are not a taste question —
/// nine frames on a landscape iPad want 3×3, the same nine on a phone want 2×5,
/// and hardcoding either makes the other one a strip of stamps.
enum SurveyLayout {

    /// Columns for `count` photos of roughly `aspectRatio`, filling `canvas`.
    ///
    /// Returns at least 1 and never more than `count`. `spacing` is counted
    /// because it is not noise at these sizes: twelve tiles on a phone lose a
    /// third of their width to gaps, and a layout chosen without them picks a
    /// column count that then does not fit.
    static func columns(
        count: Int,
        canvas: CGSize,
        aspectRatio: CGFloat,
        spacing: CGFloat = 8
    ) -> Int {
        guard count > 1 else { return 1 }
        guard canvas.width > 0, canvas.height > 0, aspectRatio > 0 else { return 1 }

        var best = 1
        var bestArea: CGFloat = -1
        for columns in 1...count {
            let area = tileArea(
                count: count,
                columns: columns,
                canvas: canvas,
                aspectRatio: aspectRatio,
                spacing: spacing
            )
            // Strictly greater, so a tie keeps the fewer columns — bigger rows
            // read better than a wide sparse one when the area is the same.
            if area > bestArea + 0.001 {
                bestArea = area
                best = columns
            }
        }
        return best
    }

    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return Int((Double(count) / Double(columns)).rounded(.up))
    }

    /// The area one tile gets at this column count, aspect-fitted into its cell.
    /// Exposed so the tests can assert the choice is genuinely the biggest one
    /// rather than re-deriving the arithmetic they are checking.
    static func tileArea(
        count: Int,
        columns: Int,
        canvas: CGSize,
        aspectRatio: CGFloat,
        spacing: CGFloat = 8
    ) -> CGFloat {
        guard count > 0, columns > 0, aspectRatio > 0 else { return 0 }
        let rowCount = rows(count: count, columns: columns)
        let cellWidth = (canvas.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (canvas.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
        guard cellWidth > 0, cellHeight > 0 else { return 0 }
        return EditorLayoutMetrics.fittedArea(
            aspectRatio: aspectRatio,
            in: CGSize(width: cellWidth, height: cellHeight)
        )
    }

    /// The aspect ratio a mixed selection is laid out at: the mean of the
    /// frames' own ratios. A survey of eight landscapes and one portrait is a
    /// landscape survey, and laying it out for the odd frame wastes the width
    /// the other eight needed.
    static func averageAspectRatio(_ ratios: [CGFloat]) -> CGFloat {
        let usable = ratios.filter { $0 > 0 }
        guard !usable.isEmpty else { return 1 }
        return usable.reduce(0, +) / CGFloat(usable.count)
    }
}
