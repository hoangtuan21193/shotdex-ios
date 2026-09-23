import Foundation

/// How bright one frame is where it meets another.
public struct PanoramaOverlapBrightness: Sendable {
    public var a: Int
    public var b: Int
    /// Mean linear intensity of frame `a` over the shared area.
    public var meanA: Double
    /// Mean linear intensity of frame `b` over the same area.
    public var meanB: Double
    /// How many pixels that area is, used to weight the fit: a sliver of
    /// overlap should not outvote half a frame.
    public var pixelCount: Int

    public init(a: Int, b: Int, meanA: Double, meanB: Double, pixelCount: Int) {
        self.a = a
        self.b = b
        self.meanA = meanA
        self.meanB = meanB
        self.pixelCount = pixelCount
    }
}

/// Works out what each frame must be multiplied by so the seams stop showing.
///
/// Solved **in the log domain**, which is the whole point of this file. The
/// usual formulation puts the gains themselves in a linear system; the spike
/// measured that drifting 10–19% away from the truth once the frames carry
/// vignetting, because the system it builds is not symmetric in the two frames
/// of a pair and the error compounds along a row. Taking logs makes the
/// relation between a pair a difference rather than a ratio, the system
/// symmetric, and the measured error 1.3–2.7%.
///
/// Works on linear intensities. Handing it gamma-encoded values would have it
/// solve for the wrong thing — exposure is linear in light, not in the numbers
/// a JPEG stores.
public enum PanoramaGainSolver {

    /// How hard the fit is pulled back towards "change nothing".
    ///
    /// Without it the answer is only defined up to a constant — making every
    /// frame twice as bright fits the seams exactly as well — and the solver
    /// would drift the whole panorama. With it the brightness of the set stays
    /// roughly where the photographer put it, and only the differences between
    /// frames move.
    static let anchorWeight = 0.1

    /// The furthest a frame may be pushed. A frame that needs more than this is
    /// not a frame with a different exposure, it is a frame of something else,
    /// and quietly multiplying it by four would be worse than leaving it.
    public static let gainLimits = 0.25...4.0

    /// One multiplier per frame, in frame order.
    ///
    /// Frames with no overlap at all come back at 1: nothing was measured
    /// about them, and inventing a correction is not the same as having one.
    public static func gains(
        frameCount: Int,
        overlaps: [PanoramaOverlapBrightness]
    ) -> [Double] {
        guard frameCount > 0 else { return [] }
        guard !overlaps.isEmpty else { return Array(repeating: 1, count: frameCount) }

        // Normal equations for: minimise Σ w_ij (g_i − g_j − d_ij)² + λ Σ g_i²,
        // where g is log gain and d_ij = log(mean_b / mean_a).
        var normal = [[Double]](
            repeating: [Double](repeating: 0, count: frameCount + 1), count: frameCount
        )
        for index in 0..<frameCount {
            normal[index][index] = anchorWeight
        }

        for overlap in overlaps {
            guard overlap.a < frameCount, overlap.b < frameCount,
                  overlap.meanA > 1e-6, overlap.meanB > 1e-6,
                  overlap.pixelCount > 0
            else { continue }
            let weight = Double(overlap.pixelCount).squareRoot()
            let difference = Foundation.log(overlap.meanB / overlap.meanA)
            let (i, j) = (overlap.a, overlap.b)
            normal[i][i] += weight
            normal[j][j] += weight
            normal[i][j] -= weight
            normal[j][i] -= weight
            normal[i][frameCount] += weight * difference
            normal[j][frameCount] -= weight * difference
        }

        guard let logGains = PanoramaMatcher.solve(normal) else {
            return Array(repeating: 1, count: frameCount)
        }
        return logGains.map { value in
            let gain = Foundation.exp(value)
            guard gain.isFinite else { return 1 }
            return min(gainLimits.upperBound, max(gainLimits.lowerBound, gain))
        }
    }

    /// How much brightness still jumps across each seam once the gains are
    /// applied, as a fraction. AC-9 asks this to average 2% or less.
    public static func residuals(
        gains: [Double],
        overlaps: [PanoramaOverlapBrightness]
    ) -> [Double] {
        overlaps.compactMap { overlap in
            guard overlap.a < gains.count, overlap.b < gains.count,
                  overlap.meanA > 1e-6, overlap.meanB > 1e-6
            else { return nil }
            let left = gains[overlap.a] * overlap.meanA
            let right = gains[overlap.b] * overlap.meanB
            let average = (left + right) / 2
            guard average > 1e-9 else { return nil }
            return abs(left - right) / average
        }
    }
}
