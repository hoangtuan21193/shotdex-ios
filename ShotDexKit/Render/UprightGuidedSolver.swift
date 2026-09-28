import CoreGraphics
import Foundation

/// Upright Guided (FS-03.15b §4): the transform that makes the lines the
/// photographer drew straight — near-vertical ones vertical, near-horizontal
/// ones horizontal. One guide can only say which way is up, so it only
/// rotates; two or more pin down the perspective too.
public enum UprightGuidedSolver {

    /// `guides` in photo coordinates (0…1, top-left origin); `aspect` is the
    /// photo's width over its height.
    public static func solve(_ guides: [PhotoUprightGuide], aspect: Double) -> PhotoUprightTransform {
        let extent = CGRect(x: 0, y: 0, width: max(0.01, aspect) * 1000, height: 1000)
        let lines = guides.prefix(PhotoUprightRecipe.maximumGuides).map { guide in
            (point(guide.start, extent), point(guide.end, extent))
        }.filter { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) > 1 }
        guard !lines.isEmpty else { return .identity }

        var best = PhotoUprightTransform.identity
        // Rotation alone first: the mean miss is exactly the turn that fixes it.
        let rotationOnly = -meanMiss(lines, transform: .identity, extent: extent) / 0.35
        best.rotate = clamp(rotationOnly)
        guard lines.count >= 2 else { return best }

        // Then the three together, by shrinking coordinate search: cheap for
        // three unknowns and four lines, and free of derivatives.
        var cost = totalCost(lines, transform: best, extent: extent)
        var step = 0.1
        while step > 1e-5 {
            var improved = false
            for axis in 0..<3 {
                for direction in [1.0, -1.0] {
                    var candidate = best
                    switch axis {
                    case 0: candidate.rotate = clamp(candidate.rotate + direction * step)
                    case 1: candidate.vertical = clamp(candidate.vertical + direction * step)
                    default: candidate.horizontal = clamp(candidate.horizontal + direction * step)
                    }
                    let candidateCost = totalCost(lines, transform: candidate, extent: extent)
                    if candidateCost < cost - 1e-15 {
                        best = candidate
                        cost = candidateCost
                        improved = true
                    }
                }
            }
            if !improved { step /= 2 }
        }
        return best
    }

    /// How far a line sits off its target, in radians, once `map` has moved
    /// it. Near-vertical (over 45° from level in the photo) aims at vertical.
    static func miss(_ line: (CGPoint, CGPoint), map: GeoForwardMap) -> Double {
        let a = map.apply(line.0), b = map.apply(line.1)
        var angle = atan2(Double(b.y - a.y), Double(b.x - a.x))
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        let source = atan2(Double(line.1.y - line.0.y), Double(line.1.x - line.0.x))
        let isUpright = abs(sin(source)) > sin(.pi / 4)
        if isUpright {
            return angle > 0 ? angle - .pi / 2 : angle + .pi / 2
        }
        return angle
    }

    private static func meanMiss(_ lines: [(CGPoint, CGPoint)], transform: PhotoUprightTransform, extent: CGRect) -> Double {
        let map = GeoForwardMap(adjustments: .zero, upright: transform, extent: extent)
        return lines.map { miss($0, map: map) }.reduce(0, +) / Double(lines.count)
    }

    private static func totalCost(_ lines: [(CGPoint, CGPoint)], transform: PhotoUprightTransform, extent: CGRect) -> Double {
        let map = GeoForwardMap(adjustments: .zero, upright: transform, extent: extent)
        return lines.map { pow(miss($0, map: map), 2) }.reduce(0, +)
    }

    private static func point(_ normalized: NormalizedPoint, _ extent: CGRect) -> CGPoint {
        CGPoint(x: normalized.x * extent.width, y: (1 - normalized.y) * extent.height)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
