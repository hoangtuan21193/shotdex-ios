import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.10 AC-1, AC-2, AC-4 at the aligner: a synthetic bracket whose true
/// geometry is known, with the sharp band moving down the frame as focus racks
/// and the picture growing as the lens breathes.
struct FocusStackAlignmentTests {

    let width = 480, height = 360

    // MARK: Fixture

    private func bracket(count: Int, breathing: Double, seed: UInt64 = 1)
        -> (frames: [CGImage], sceneFromFrame: [CGAffineTransform]) {
        let bracket = FocusStackFixture(width: width, height: height, seed: seed).bracket(count: count, breathing: breathing)
        return (bracket.frames, bracket.sceneFromFrame)
    }

    /// Mean distance, over a grid inside the frame, between where the aligner
    /// sends a frame pixel and where it truly belongs in frame 0.
    private func error(_ estimated: CGAffineTransform, truth: CGAffineTransform) -> Double {
        var total = 0.0, n = 0.0
        for gy in 1..<8 { for gx in 1..<8 {
            let p = CGPoint(x: Double(gx) / 8 * Double(width), y: Double(gy) / 8 * Double(height))
            let a = p.applying(estimated), b = p.applying(truth)
            total += hypot(a.x - b.x, a.y - b.y); n += 1
        } }
        return total / n
    }

    private func truth(_ maps: [CGAffineTransform], _ k: Int) -> CGAffineTransform {
        // frame k pixel → scene → frame 0 pixel
        maps[k].concatenating(maps[0].inverted())
    }

    // MARK: Tests

    @Test(arguments: [0.0, 0.02, 0.05])
    func breathingBracketLinesUpWithinAPixel(breathing: Double) {
        let (frames, maps) = bracket(count: 6, breathing: breathing)
        let result = FocusStackAligner.align(frames)
        #expect(result.count == frames.count)
        for k in frames.indices {
            guard let estimated = result[k] else {
                Issue.record("frame \(k) did not line up at \(breathing)")
                continue
            }
            #expect(error(estimated, truth: truth(maps, k)) <= 1.0, "frame \(k), breathing \(breathing)")
        }
    }

    @Test func aFrameFromAnotherSceneIsLeftOutAndTheChainGoesOn() {
        var (frames, maps) = bracket(count: 6, breathing: 0.02)
        let stranger = bracket(count: 1, breathing: 0, seed: 777).frames[0]
        frames.insert(stranger, at: 3)
        maps.insert(.identity, at: 3)
        let result = FocusStackAligner.align(frames)
        #expect(result[3] == nil)
        for k in frames.indices where k != 3 {
            guard let estimated = result[k] else { Issue.record("frame \(k) lost"); continue }
            #expect(error(estimated, truth: truth(maps, k)) <= 1.0, "frame \(k)")
        }
    }

    @Test func theFirstFrameIsTheReference() {
        let result = FocusStackAligner.align(bracket(count: 3, breathing: 0.02).frames)
        #expect(result.first == .identity)
    }

    @Test func aSimilarityIsRecoveredExactlyFromTwoPoints() {
        let t = CGAffineTransform(a: 1.03 * cos(0.01), b: 1.03 * sin(0.01), c: -1.03 * sin(0.01), d: 1.03 * cos(0.01), tx: 4, ty: -2)
        let src: [SIMD2<Double>] = [SIMD2(10, 20), SIMD2(300, 180)]
        let dst = src.map { p -> SIMD2<Double> in
            let q = CGPoint(x: p.x, y: p.y).applying(t); return SIMD2(q.x, q.y)
        }
        let fit = FocusStackAligner.similarity(src: src, dst: dst)!
        #expect(abs(fit.a - t.a) < 1e-9 && abs(fit.b - t.b) < 1e-9 && abs(fit.tx - t.tx) < 1e-6 && abs(fit.ty - t.ty) < 1e-6)
    }
}
