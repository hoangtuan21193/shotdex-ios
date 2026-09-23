import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-3 — every frame ends up in one consistent set of orientations, and
/// the answer does not depend on the order the photos were selected in.
///
/// The cameras here are invented and then recovered, so "how wrong is it" is a
/// number in degrees rather than a judgement about a picture.
struct PanoramaSolverTests {

    private let width = 800
    private let height = 600
    private let focal = 900.0

    private var centreX: Double { Double(width) / 2 }
    private var centreY: Double { Double(height) / 2 }

    /// A camera turned by yaw and pitch, in degrees.
    private func camera(yaw: Double, pitch: Double = 0, roll: Double = 0) -> [Double] {
        let y = PanoramaRotation.matrix(fromAxisAngle: (0, yaw * .pi / 180, 0))
        let p = PanoramaRotation.matrix(fromAxisAngle: (pitch * .pi / 180, 0, 0))
        let r = PanoramaRotation.matrix(fromAxisAngle: (0, 0, roll * .pi / 180))
        return PanoramaRotation.multiply(PanoramaRotation.multiply(y, p), r)
    }

    /// The homography between two frames of the same rotating camera.
    private func homography(from a: [Double], to b: [Double]) -> PanoramaHomography {
        let k = [focal, 0, centreX, 0, focal, centreY, 0, 0, 1]
        let kInverse = [1 / focal, 0, -centreX / focal, 0, 1 / focal, -centreY / focal, 0, 0, 1]
        let relative = PanoramaRotation.multiply(PanoramaRotation.transposed(b), a)
        return PanoramaHomography(
            PanoramaRotation.multiply(k, PanoramaRotation.multiply(relative, kInverse))
        )!
    }

    /// Points visible in both frames, as the matcher would have handed them
    /// over: a grid in the first frame, mapped through the truth into the
    /// second, keeping only what actually lands inside it.
    private func correspondences(
        from a: [Double],
        to b: [Double]
    ) -> [(ax: Double, ay: Double, bx: Double, by: Double)] {
        let h = homography(from: a, to: b)
        var points: [(ax: Double, ay: Double, bx: Double, by: Double)] = []
        for row in 0..<9 {
            for column in 0..<9 {
                let x = 40 + Double(column) / 8 * Double(width - 80)
                let y = 40 + Double(row) / 8 * Double(height - 80)
                guard let mapped = h.map(x: x, y: y),
                      mapped.x > 0, mapped.y > 0,
                      mapped.x < Double(width), mapped.y < Double(height)
                else { continue }
                points.append((x, y, mapped.x, mapped.y))
            }
        }
        return points
    }

    private func observation(_ a: Int, _ b: Int, _ cameras: [[Double]]) -> PanoramaPairObservation? {
        let points = correspondences(from: cameras[a], to: cameras[b])
        guard points.count >= 8 else { return nil }
        return PanoramaPairObservation(
            a: a, b: b, homography: homography(from: cameras[a], to: cameras[b]), correspondences: points
        )
    }

    // MARK: Focal length

    @Test func theFocalLengthIsRecoveredFromTheOverlapsAlone() throws {
        let cameras = [camera(yaw: 0), camera(yaw: 22), camera(yaw: 44)]
        let pairs = [observation(0, 1, cameras), observation(1, 2, cameras)].compactMap { $0 }
        let estimate = try #require(
            PanoramaCameraSolver.estimateFocal(
                pairs: pairs, centreX: centreX, centreY: centreY, longEdge: Double(width)
            )
        )
        // Within a fraction of a percent: the spike measured 0.00-0.15%.
        #expect(abs(estimate - focal) / focal < 0.01)
    }

    // MARK: Orientations

    @Test func aRowOfFramesComesBackWithTheRotationsItWasBuiltFrom() throws {
        let truth = [camera(yaw: -30), camera(yaw: -15), camera(yaw: 0), camera(yaw: 15), camera(yaw: 30)]
        let pairs = (0..<4).compactMap { observation($0, $0 + 1, truth) }
        let solution = try #require(
            PanoramaCameraSolver.solve(
                frameCount: truth.count, imageWidth: width, imageHeight: height, pairs: pairs
            )
        )
        #expect(solution.cameras.count == truth.count)
        #expect(solution.unplaced.isEmpty)
        #expect(solution.reprojectionError < 0.5)

        // Absolute orientation is arbitrary — nothing in the pictures says
        // which way north is — so the check is on angles *between* frames.
        for index in 0..<(truth.count - 1) {
            let expected = PanoramaRotation.angleBetween(truth[index], truth[index + 1])
            let actual = PanoramaRotation.angleBetween(
                solution.cameras[index]!.rotation, solution.cameras[index + 1]!.rotation
            )
            #expect(abs(expected - actual) < 0.1, "frames \(index)-\(index + 1) drifted")
        }
    }

    /// AC-3's second half: the same photos in a different order are the same
    /// panorama. A photographer's multi-select order is not the shooting order.
    @Test func theOrderTheFramesArriveInDoesNotChangeTheAnswer() throws {
        let truth = [camera(yaw: -20), camera(yaw: 0), camera(yaw: 20), camera(yaw: 40)]
        let forward = (0..<3).compactMap { observation($0, $0 + 1, truth) }
        let shuffled: [PanoramaPairObservation] = [forward[2], forward[0], forward[1]]

        func angles(_ pairs: [PanoramaPairObservation]) throws -> [Double] {
            let solution = try #require(
                PanoramaCameraSolver.solve(
                    frameCount: truth.count, imageWidth: width, imageHeight: height, pairs: pairs
                )
            )
            return (0..<(truth.count - 1)).map {
                PanoramaRotation.angleBetween(
                    solution.cameras[$0]!.rotation, solution.cameras[$0 + 1]!.rotation
                )
            }
        }
        let a = try angles(forward)
        let b = try angles(shuffled)
        for (left, right) in zip(a, b) {
            #expect(abs(left - right) < 0.05)
        }
    }

    /// AC-4: a frame from another scene has no overlap, so it forms its own
    /// group, the big group wins, and the odd one out is named rather than
    /// quietly dropped.
    @Test func aFrameFromAnotherSceneIsReportedAsNotPlaced() throws {
        let truth = [camera(yaw: -15), camera(yaw: 0), camera(yaw: 15), camera(yaw: 0)]
        // Frame 3 is connected to nothing.
        let pairs = [observation(0, 1, truth), observation(1, 2, truth)].compactMap { $0 }
        let solution = try #require(
            PanoramaCameraSolver.solve(
                frameCount: 4, imageWidth: width, imageHeight: height, pairs: pairs
            )
        )
        #expect(solution.cameras.keys.sorted() == [0, 1, 2])
        #expect(solution.unplaced == [3])
    }

    // MARK: Horizon

    /// Every frame shot with the camera rolled by the same two degrees: the
    /// solve cannot know that from the pictures, so levelling has to put it
    /// right, or the panorama renders on a slope.
    @Test func theHorizonIsPulledLevel() throws {
        let tilt = 4.0
        let truth = (0..<5).map { camera(yaw: Double($0 - 2) * 18, roll: tilt) }
        let pairs = (0..<4).compactMap { observation($0, $0 + 1, truth) }
        let solution = try #require(
            PanoramaCameraSolver.solve(
                frameCount: truth.count, imageWidth: width, imageHeight: height, pairs: pairs
            )
        )

        // After levelling, every camera's side-to-side axis lies in the
        // horizontal plane: its vertical component is what a tilt would show.
        for camera in solution.cameras.values {
            let verticalPartOfX = abs(camera.rotation[1])
            #expect(verticalPartOfX < 0.02, "a levelled camera should not be banked")
        }
    }

    @Test func rotationHelpersAgreeWithThemselves() {
        let r = PanoramaRotation.matrix(fromAxisAngle: (0.1, -0.2, 0.05))
        let identity = PanoramaRotation.multiply(r, PanoramaRotation.transposed(r))
        for (index, value) in identity.enumerated() {
            let expected = PanoramaRotation.identity[index]
            #expect(abs(value - expected) < 1e-12)
        }
        #expect(abs(PanoramaRotation.angleBetween(r, r)) < 1e-9)
        let thirty = PanoramaRotation.matrix(fromAxisAngle: (0, 30 * .pi / 180, 0))
        #expect(abs(PanoramaRotation.angleBetween(PanoramaRotation.identity, thirty) - 30) < 1e-9)
    }
}
