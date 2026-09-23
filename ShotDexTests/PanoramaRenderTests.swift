import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 — the projections and the exposure matching between frames.
struct PanoramaRenderTests {

    private let width = 800
    private let height = 600
    private let focal = 900.0

    private func camera(yaw: Double, pitch: Double = 0) -> PanoramaCamera {
        let y = PanoramaRotation.matrix(fromAxisAngle: (0, yaw * .pi / 180, 0))
        let p = PanoramaRotation.matrix(fromAxisAngle: (pitch * .pi / 180, 0, 0))
        return PanoramaCamera(rotation: PanoramaRotation.multiply(y, p))
    }

    private func availability(
        _ cameras: [PanoramaCamera]
    ) -> [PanoramaProjectionKind: PanoramaProjectionAvailability] {
        let list = PanoramaProjection.availability(
            cameras: cameras, focal: focal, imageWidth: width, imageHeight: height
        )
        return Dictionary(uniqueKeysWithValues: list.map { ($0.kind, $0) })
    }

    // MARK: The maps

    @Test(arguments: PanoramaProjectionKind.allCases)
    func everyProjectionUndoesItself(kind: PanoramaProjectionKind) throws {
        // A direction well inside every projection's range.
        let direction = (0.3, 0.2, 0.93)
        let length = (direction.0 * direction.0 + direction.1 * direction.1 + direction.2 * direction.2)
            .squareRoot()
        let unit = (direction.0 / length, direction.1 / length, direction.2 / length)

        let projected = try #require(PanoramaProjection.project(unit, kind: kind, focal: focal))
        let back = try #require(
            PanoramaProjection.unproject(u: projected.u, v: projected.v, kind: kind, focal: focal)
        )
        // Perspective comes back on the z = 1 plane rather than the unit
        // sphere, so compare directions, not coordinates.
        let backLength = (back.0 * back.0 + back.1 * back.1 + back.2 * back.2).squareRoot()
        let backUnit = (back.0 / backLength, back.1 / backLength, back.2 / backLength)
        #expect(abs(backUnit.0 - unit.0) < 1e-9)
        #expect(abs(backUnit.1 - unit.1) < 1e-9)
        #expect(abs(backUnit.2 - unit.2) < 1e-9)
    }

    // MARK: AC-7 — which projections a set can be built with

    /// A wide sweep: spherical and cylindrical stand, perspective cannot be
    /// built and says why.
    @Test func aWideSweepRulesOutPerspective() throws {
        let cameras = stride(from: -130.0, through: 130.0, by: 26).map { camera(yaw: $0) }
        let result = availability(cameras)
        #expect(result[.spherical]?.isAvailable == true)
        #expect(result[.cylindrical]?.isAvailable == true)
        let perspective = try #require(result[.perspective])
        #expect(!perspective.isAvailable)
        guard case .horizontalSweepTooWide = perspective.reason else {
            Issue.record("a wide sweep should be refused for being wide, got \(String(describing: perspective.reason))")
            return
        }
    }

    /// A sweep from the ground to overhead: cylindrical runs to infinity, but
    /// spherical still holds it.
    @Test func aTallSweepRulesOutCylindrical() throws {
        let cameras = stride(from: -80.0, through: 80.0, by: 20).map { camera(yaw: 0, pitch: $0) }
        let result = availability(cameras)
        #expect(result[.spherical]?.isAvailable == true)
        let cylindrical = try #require(result[.cylindrical])
        #expect(!cylindrical.isAvailable)
        guard case .verticalSweepTooWide = cylindrical.reason else {
            Issue.record("a tall sweep should be refused for being tall")
            return
        }
    }

    /// Two frames side by side are the narrow case Perspective exists for.
    @Test func aNarrowPairKeepsEveryProjection() {
        let cameras = [camera(yaw: -8), camera(yaw: 8)]
        let result = availability(cameras)
        #expect(result[.spherical]?.isAvailable == true)
        #expect(result[.cylindrical]?.isAvailable == true)
        #expect(result[.perspective]?.isAvailable == true)
    }

    // MARK: The canvas

    @Test func theCanvasHoldsEveryFrameItWasBuiltFor() throws {
        let cameras = stride(from: -30.0, through: 30.0, by: 15).map { camera(yaw: $0) }
        let canvas = try #require(
            PanoramaProjection.canvas(
                kind: .spherical, cameras: cameras, focal: focal,
                imageWidth: width, imageHeight: height
            )
        )
        #expect(canvas.width > width, "a five-frame sweep is wider than one frame")
        for direction in PanoramaProjection.boundaryDirections(
            cameras: cameras, focal: focal, imageWidth: width, imageHeight: height
        ) {
            let point = try #require(canvas.project(direction))
            #expect(point.x >= -0.5 && point.x <= Double(canvas.width) + 0.5)
            #expect(point.y >= -0.5 && point.y <= Double(canvas.height) + 0.5)
        }
    }

    /// AC-25: Size is applied to the canvas, so half the size is half the
    /// pixels each way and a quarter of the work.
    @Test func sizeScalesTheCanvasAndNothingElse() throws {
        let cameras = stride(from: -20.0, through: 20.0, by: 20).map { camera(yaw: $0) }
        let full = try #require(
            PanoramaProjection.canvas(
                kind: .spherical, cameras: cameras, focal: focal,
                imageWidth: width, imageHeight: height
            )
        )
        let half = try #require(
            PanoramaProjection.canvas(
                kind: .spherical, cameras: cameras, focal: focal,
                imageWidth: width, imageHeight: height, scale: 0.5
            )
        )
        #expect(abs(Double(half.width) - Double(full.width) / 2) <= 1)
        #expect(abs(Double(half.height) - Double(full.height) / 2) <= 1)
    }

    /// AC-8: a column of frames is projected about a turned axis, or it comes
    /// out as an hourglass that wastes most of its own canvas.
    @Test func aColumnOfFramesTurnsTheProjectionOnItsSide() throws {
        let column = stride(from: -30.0, through: 30.0, by: 15).map { camera(yaw: 0, pitch: $0) }
        let directions = PanoramaProjection.boundaryDirections(
            cameras: column, focal: focal, imageWidth: width, imageHeight: height
        )
        let frame = PanoramaProjection.projectionFrame(for: directions, kind: .spherical)
        #expect(frame != PanoramaRotation.identity, "a tall sweep should turn the axis")

        let row = stride(from: -30.0, through: 30.0, by: 15).map { camera(yaw: $0) }
        let rowDirections = PanoramaProjection.boundaryDirections(
            cameras: row, focal: focal, imageWidth: width, imageHeight: height
        )
        #expect(
            PanoramaProjection.projectionFrame(for: rowDirections, kind: .spherical)
                == PanoramaRotation.identity,
            "a normal sweep should be left alone"
        )
    }

    // MARK: AC-9 — exposure across the seams

    /// Frames given the exposure drift of a real sweep come back matched to
    /// each other, and the seams settle well inside the 2% the criterion asks
    /// for.
    @Test func exposureIsMatchedAcrossEverySeam() {
        let trueGains = [1.0, 0.82, 1.21, 0.95, 1.25, 0.8]
        // What each frame measures where it meets the next: the same scene
        // brightness divided by the exposure that frame was shot at.
        let sceneBrightness = [0.42, 0.38, 0.51, 0.33, 0.46]
        var overlaps: [PanoramaOverlapBrightness] = []
        for index in 0..<(trueGains.count - 1) {
            overlaps.append(
                PanoramaOverlapBrightness(
                    a: index,
                    b: index + 1,
                    meanA: sceneBrightness[index] / trueGains[index],
                    meanB: sceneBrightness[index] / trueGains[index + 1],
                    pixelCount: 40_000
                )
            )
        }

        let gains = PanoramaGainSolver.gains(frameCount: trueGains.count, overlaps: overlaps)
        let residuals = PanoramaGainSolver.residuals(gains: gains, overlaps: overlaps)
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        #expect(mean <= 0.02, "seams should not jump by more than 2%")

        // The recovered gains are only defined up to a constant, so compare
        // their ratios to the first frame rather than their absolute values.
        for index in 1..<trueGains.count {
            let expected = trueGains[index] / trueGains[0]
            let actual = gains[index] / gains[0]
            #expect(abs(actual - expected) / expected < 0.05)
        }
    }

    /// A frame nothing overlaps is left alone rather than invented for.
    @Test func aFrameWithNoOverlapIsNotAdjusted() {
        let overlaps = [
            PanoramaOverlapBrightness(a: 0, b: 1, meanA: 0.5, meanB: 0.4, pixelCount: 10_000)
        ]
        let gains = PanoramaGainSolver.gains(frameCount: 3, overlaps: overlaps)
        #expect(abs(gains[2] - 1) < 1e-9)
    }

    @Test func anAbsurdGainIsClamped() {
        let overlaps = [
            PanoramaOverlapBrightness(a: 0, b: 1, meanA: 0.9, meanB: 0.0005, pixelCount: 10_000)
        ]
        let gains = PanoramaGainSolver.gains(frameCount: 2, overlaps: overlaps)
        for gain in gains {
            #expect(PanoramaGainSolver.gainLimits.contains(gain))
        }
    }
}
