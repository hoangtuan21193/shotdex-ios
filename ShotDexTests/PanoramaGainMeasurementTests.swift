import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-9 — the exposure difference between two frames is read off the
/// points registration already matched.
struct PanoramaGainMeasurementTests {

    private func flat(_ level: Float, width: Int = 40, height: Int = 30) -> PanoramaImage {
        PanoramaImage(
            width: width, height: height,
            pixels: [Float](repeating: level, count: width * height)
        )
    }

    private func pair(_ a: Int, _ b: Int, count: Int) -> PanoramaPairObservation {
        let points = (0..<count).map { index -> (ax: Double, ay: Double, bx: Double, by: Double) in
            let x = Double(index % 20) + 5
            let y = Double(index / 20) + 5
            return (x, y, x, y)
        }
        return PanoramaPairObservation(
            a: a, b: b, homography: .identity, correspondences: points
        )
    }

    @Test func brightnessIsMeasuredWhereTheFramesActuallyMatched() throws {
        // Two frames of the same scene, one exposed brighter.
        let images = [flat(0.4), flat(0.6)]
        let overlaps = PanoramaGainMeasurement.overlaps(pairs: [pair(0, 1, count: 60)], images: images)
        let overlap = try #require(overlaps.first)
        #expect(overlap.a == 0)
        #expect(overlap.b == 1)
        #expect(overlap.pixelCount == 60)
        // Compared in linear light, not in the stored numbers.
        #expect(abs(overlap.meanA - PanoramaGainMeasurement.linear(0.4)) < 1e-6)
        #expect(abs(overlap.meanB - PanoramaGainMeasurement.linear(0.6)) < 1e-6)
    }

    /// Solving on the stored numbers rather than on light is the mistake the
    /// spike measured at 10–19%. The ratio the solver sees has to be the ratio
    /// of exposures, and in gamma-encoded values it is not.
    @Test func theRatioIsOfLightNotOfStoredNumbers() {
        let gammaRatio = 0.6 / 0.4
        let linearRatio = PanoramaGainMeasurement.linear(0.6) / PanoramaGainMeasurement.linear(0.4)
        #expect(abs(linearRatio - gammaRatio) > 0.5, "the two differ enough to matter: \(linearRatio) vs \(gammaRatio)")
    }

    @Test func aPairWithTooFewPointsIsNotMeasured() {
        let overlaps = PanoramaGainMeasurement.overlaps(
            pairs: [pair(0, 1, count: 4)], images: [flat(0.4), flat(0.6)]
        )
        #expect(overlaps.isEmpty)
    }

    /// End to end with the solver: frames given known exposures come back
    /// matched to each other.
    @Test func measuredOverlapsFeedTheSolver() {
        let levels: [Float] = [0.45, 0.30, 0.55, 0.38]
        let images = levels.map { flat($0) }
        let pairs = (0..<(levels.count - 1)).map { pair($0, $0 + 1, count: 100) }
        let overlaps = PanoramaGainMeasurement.overlaps(pairs: pairs, images: images)
        #expect(overlaps.count == 3)

        let gains = PanoramaGainSolver.gains(frameCount: levels.count, overlaps: overlaps)
        let residuals = PanoramaGainSolver.residuals(gains: gains, overlaps: overlaps)
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        #expect(mean <= 0.02, "seams should settle, got \(mean)")
    }
}
