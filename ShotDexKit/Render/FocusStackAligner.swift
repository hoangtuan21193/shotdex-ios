import CoreGraphics
import Foundation

/// Lines up the frames of a focus bracket (FS-01.10 §4).
///
/// A macro lens changes magnification as it racks focus ("focus breathing"),
/// so a bracket drifts by scale as well as by shift. The fit is a similarity —
/// scale, rotation, shift, four degrees of freedom — and not a full homography:
/// a bracket is shot from a tripod or a rail, so nothing but those four moves,
/// and fitting eight parameters to that mostly fits the noise.
///
/// Each frame is registered to its **neighbour**, not to the first frame. Two
/// frames far apart in the bracket are sharp in different places and share
/// almost no detail — in the spike, registering straight to the first frame
/// failed on 7 of 15 frames, and chaining failed on none.
public enum FocusStackAligner {
    /// Farthest a point may land from where the fit says, in working-image
    /// pixels, and still agree with it.
    public static let inlierThreshold = 2.0
    /// The fewest agreeing points a step may have. A similarity has four
    /// degrees of freedom; agreement from a handful of points means nothing.
    public static let minimumInliers = 20
    /// Steps outside these are refused rather than trusted: no lens breathes
    /// 25% between two neighbouring frames, and nobody rotates a rail.
    public static let scaleRange: ClosedRange<Double> = 0.85...1.18
    public static let maximumRotationDegrees = 4.0

    /// For each frame, the map taking its pixels (top-left origin, at the
    /// frames' own resolution) onto the first frame's, or nil when the frame
    /// could not be lined up. The first frame is always the identity.
    ///
    /// A frame that fails does not break the chain: the next one registers to
    /// the last frame that succeeded.
    public static func align(_ frames: [CGImage]) -> [CGAffineTransform?] {
        guard let first = frames.first else { return [] }
        let working = frames.map { PanoramaImage.luminance(of: $0) }
        // Working images all share the first frame's scale factor; frames of one
        // bracket are one size (the renderer fits any that are not).
        let scale = Double(first.width) / Double(working[0]?.width ?? first.width)
        let features = working.map { image in image.map { PanoramaFeatureDetector.features(in: $0, maximumCount: 2_000) } ?? [] }

        var result: [CGAffineTransform?] = [.identity]
        var lastGood = 0
        var lastGoodToFirst = CGAffineTransform.identity
        for index in frames.indices.dropFirst() {
            guard let step = fit(from: features[index], to: features[lastGood]) else {
                result.append(nil)
                continue
            }
            // Working pixels → full pixels: the similarity's shift scales, its
            // scale and rotation do not.
            let full = CGAffineTransform(a: step.a, b: step.b, c: step.c, d: step.d,
                                         tx: step.tx * scale, ty: step.ty * scale)
            let toFirst = full.concatenating(lastGoodToFirst)
            result.append(toFirst)
            lastGood = index
            lastGoodToFirst = toFirst
        }
        return result
    }

    /// The similarity taking `source` feature positions onto `target`'s, by
    /// RANSAC over two-point samples, refit on every inlier. Nil when too few
    /// points agree or the answer is not a plausible step.
    static func fit(from source: [PanoramaFeature], to target: [PanoramaFeature]) -> CGAffineTransform? {
        let matches = PanoramaMatcher.matches(source, target)
        guard matches.count >= minimumInliers else { return nil }
        let src = matches.map { SIMD2(Double(source[$0.a].x), Double(source[$0.a].y)) }
        let dst = matches.map { SIMD2(Double(target[$0.b].x), Double(target[$0.b].y)) }

        // Seeded, so a bracket aligns the same way every time it is opened.
        var generator = SplitMix64(seed: UInt64(matches.count) &* 0x9E37_79B9)
        var best: [Int] = []
        for _ in 0..<600 {
            let i = Int(generator.next() % UInt64(src.count))
            let j = Int(generator.next() % UInt64(src.count))
            guard i != j, let candidate = similarity(src: [src[i], src[j]], dst: [dst[i], dst[j]]) else { continue }
            let inliers = src.indices.filter { distance(candidate, src[$0], dst[$0]) < inlierThreshold }
            if inliers.count > best.count { best = inliers }
        }
        guard best.count >= minimumInliers,
              let refined = similarity(src: best.map { src[$0] }, dst: best.map { dst[$0] })
        else { return nil }
        let stepScale = hypot(refined.a, refined.b)
        let degrees = abs(atan2(refined.b, refined.a)) * 180 / .pi
        guard scaleRange.contains(stepScale), degrees <= maximumRotationDegrees else { return nil }
        return refined
    }

    /// Least-squares similarity `dst ≈ [a −b; b a]·src + t` from two or more pairs.
    static func similarity(src: [SIMD2<Double>], dst: [SIMD2<Double>]) -> CGAffineTransform? {
        guard src.count >= 2, src.count == dst.count else { return nil }
        // Centre both sets: the rotation-scale part then solves in closed form.
        let n = Double(src.count)
        let cs = src.reduce(SIMD2<Double>(0, 0), +) / n
        let cd = dst.reduce(SIMD2<Double>(0, 0), +) / n
        var sxx = 0.0, sxy = 0.0, norm = 0.0
        for (p, q) in zip(src, dst) {
            let a = p - cs, b = q - cd
            sxx += a.x * b.x + a.y * b.y
            sxy += a.x * b.y - a.y * b.x
            norm += a.x * a.x + a.y * a.y
        }
        guard norm > 1e-9 else { return nil }
        let a = sxx / norm, b = sxy / norm
        let tx = cd.x - (a * cs.x - b * cs.y)
        let ty = cd.y - (b * cs.x + a * cs.y)
        // CGAffineTransform maps (x, y) → (a·x + c·y + tx, b·x + d·y + ty).
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    @inline(__always)
    static func distance(_ t: CGAffineTransform, _ p: SIMD2<Double>, _ q: SIMD2<Double>) -> Double {
        let x = t.a * p.x + t.c * p.y + t.tx, y = t.b * p.x + t.d * p.y + t.ty
        return hypot(x - q.x, y - q.y)
    }
}
