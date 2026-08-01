import Foundation

/// The Light group's `Auto` button. The suggestion is derived from the histogram
/// the editor already samples for display, so it needs no extra render pass and
/// is deterministic for a given histogram — which also makes it testable.
enum EditorAutoTone {
    /// Bins below this normalized height are treated as empty. The display
    /// histogram is percentile-normalized and square-rooted, so a real tone still
    /// lands well above this floor.
    private static let populatedThreshold = 0.06

    static func suggestion(
        for adjustments: PhotoAdjustments,
        histogram: PhotoHistogram
    ) -> PhotoAdjustments {
        let luminance = histogram.luminance
        guard luminance.count > 1 else { return adjustments }
        let populated = luminance.indices.filter { luminance[$0] > populatedThreshold }
        guard let first = populated.first, let last = populated.last else { return adjustments }

        let maximumIndex = Double(luminance.count - 1)
        let lowest = Double(first) / maximumIndex
        let highest = Double(last) / maximumIndex
        let weightSum = luminance.reduce(0, +)
        let centroid = weightSum > 0
            ? luminance.indices.reduce(0.0) { $0 + Double($1) * luminance[$1] }
                / (weightSum * maximumIndex)
            : 0.5

        var result = adjustments
        // Aim the tonal centre of mass just below mid-grey, the exposure most
        // photographs read as correct, and keep the correction gentle.
        result.exposure = clamped((0.45 - centroid) * 1.6, to: 0.75)
        // Headroom above the brightest tone becomes Whites; crushed shadows are
        // left alone because lifting them would mostly amplify noise.
        result.whites = clamped((1 - highest) * 1.6, to: 0.6)
        // A histogram bunched into a narrow band gets contrast back.
        let span = max(0, highest - lowest)
        result.contrast = span < 0.6 ? clamped((0.6 - span) * 0.8, to: 0.35) : 0
        return result
    }

    private static func clamped(_ value: Double, to limit: Double) -> Double {
        let rounded = (value * 100).rounded() / 100
        return min(limit, max(-limit, rounded))
    }
}
