import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-23 — someone who walked through the overlap between two shutter
/// presses comes out whole or not at all, never cut in half and never twice.
///
/// The scene here is two frames of the same wall, overlapping down a strip in
/// the middle, with a dark figure standing in that strip in one frame and
/// gone from the other. A join down the middle of the overlap would run
/// straight through them; the join this finds has to go round.
struct PanoramaSeamTests {

    private let width = 120
    private let height = 80
    /// The overlap: the middle third of the canvas.
    private let overlap = 40..<80

    /// Flat wall with a little texture, identical in both frames.
    private func wall() -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = 0.55 + 0.02 * Float((x % 7) + (y % 5)) / 10
            }
        }
        return pixels
    }

    private func coverage(_ range: Range<Int>) -> [Float] {
        var mask = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in range { mask[y * width + x] = 1 }
        }
        return mask
    }

    /// Where the figure stands: a block inside the overlap.
    private let figure = (x: 52..<66, y: 20..<70)

    private func withFigure(_ base: [Float]) -> [Float] {
        var pixels = base
        for y in figure.y {
            for x in figure.x { pixels[y * width + x] = 0.08 }
        }
        return pixels
    }

    private func isFigure(_ index: Int) -> Bool {
        let x = index % width, y = index / width
        return figure.x.contains(x) && figure.y.contains(y)
    }

    // MARK: AC-23

    /// The person is in frame A and not in frame B. Whichever way the join
    /// goes, every pixel of them has to come from one frame — all of A, so
    /// they are there, or all of B, so they are not.
    @Test func theJoinDoesNotCutThroughSomeoneWhoMoved() throws {
        let a = withFigure(wall())
        let b = wall()
        let owned = try #require(
            PanoramaSeamFinder.ownership(
                a: a,
                b: b,
                coverageA: coverage(0..<80),
                coverageB: coverage(40..<width),
                width: width,
                height: height
            )
        )
        let onFigure = Set((0..<(width * height)).filter(isFigure).map { owned[$0] })
        #expect(onFigure.count == 1, "the join cut the figure in two")
    }

    /// And the join is not simply refusing to enter the overlap: it stays
    /// inside it, which is the whole point of `outsideCost`.
    @Test func theJoinStaysInsideTheOverlap() throws {
        let a = withFigure(wall())
        let b = wall()
        let coverageA = coverage(0..<80), coverageB = coverage(40..<width)
        let cost = try #require(
            PanoramaSeamFinder.cost(
                a: a, b: b, coverageA: coverageA, coverageB: coverageB,
                width: width, height: height
            )
        )
        let seam = try #require(
            PanoramaSeamFinder.path(cost: cost, width: width, height: height, axis: .vertical)
        )
        #expect(seam.allSatisfy { overlap.contains($0) }, "seam left the overlap: \(seam.min()!)…\(seam.max()!)")
    }

    /// A join that went round the figure has to come back: it is one path, so
    /// it moves by at most a pixel per row. This is what keeps it from being
    /// a per-row argmin that tears.
    @Test func theJoinIsContinuous() throws {
        let a = withFigure(wall())
        let b = wall()
        let cost = try #require(
            PanoramaSeamFinder.cost(
                a: a, b: b,
                coverageA: coverage(0..<80), coverageB: coverage(40..<width),
                width: width, height: height
            )
        )
        let seam = try #require(
            PanoramaSeamFinder.path(cost: cost, width: width, height: height, axis: .vertical)
        )
        for row in 1..<seam.count {
            #expect(abs(seam[row] - seam[row - 1]) <= 1)
        }
    }

    /// Nothing moved: the join is free to run anywhere the frames agree, and
    /// what matters is that it still produces a picture — every pixel owned by
    /// a frame that actually covers it.
    @Test func aStillSceneIsOwnedByWhoeverCoversIt() throws {
        let still = wall()
        let coverageA = coverage(0..<80), coverageB = coverage(40..<width)
        let owned = try #require(
            PanoramaSeamFinder.ownership(
                a: still, b: still,
                coverageA: coverageA, coverageB: coverageB,
                width: width, height: height
            )
        )
        for index in 0..<(width * height) {
            let covered = owned[index] ? coverageA[index] : coverageB[index]
            #expect(covered > 0, "pixel \(index) given to a frame that cannot see it")
        }
    }

    // MARK: The path itself

    /// A valley of zeros in a field of ones, wandering a pixel per row — which
    /// is exactly as fast as a seam is allowed to move, so it is a legal path
    /// and the only free one.
    @Test func theCheapestPathFollowsTheValley() throws {
        let width = 9, height = 9
        let wander = [0, 1, 0, -1]
        var cost = [Float](repeating: 1, count: width * height)
        var valley: [Int] = []
        for y in 0..<height {
            let x = 4 + wander[y % wander.count]
            valley.append(x)
            cost[y * width + x] = 0
        }
        let seam = try #require(
            PanoramaSeamFinder.path(cost: cost, width: width, height: height, axis: .vertical)
        )
        #expect(seam == valley)
    }

    /// The same recurrence, turned on its side, for frames stacked rather than
    /// side by side.
    @Test func theHorizontalPathFollowsItsOwnValley() throws {
        let width = 9, height = 9
        let wander = [0, 1, 0, -1]
        var cost = [Float](repeating: 1, count: width * height)
        var valley: [Int] = []
        for x in 0..<width {
            let y = 4 + wander[x % wander.count]
            valley.append(y)
            cost[y * width + x] = 0
        }
        let seam = try #require(
            PanoramaSeamFinder.path(cost: cost, width: width, height: height, axis: .horizontal)
        )
        #expect(seam == valley)
    }

    /// A tall narrow overlap is two frames side by side, so the join runs down
    /// it; a wide flat one is two frames stacked, so it runs across.
    @Test func theAxisFollowsTheShapeOfTheOverlap() {
        #expect(PanoramaSeamFinder.Axis.across(width: 40, height: 400) == .vertical)
        #expect(PanoramaSeamFinder.Axis.across(width: 400, height: 40) == .horizontal)
    }

    @Test func refusesBuffersThatDoNotMatchTheSize() {
        #expect(
            PanoramaSeamFinder.cost(
                a: [0, 0], b: [0, 0], coverageA: [1, 1], coverageB: [1, 1], width: 4, height: 4
            ) == nil
        )
        #expect(PanoramaSeamFinder.path(cost: [], width: 0, height: 0, axis: .vertical) == nil)
    }
}
