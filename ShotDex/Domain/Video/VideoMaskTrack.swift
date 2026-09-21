import CoreGraphics
import Foundation
import ShotDexKit

/// Where a tracked window is at one moment, relative to where it was drawn.
///
/// Stored as a **delta**, not an absolute position: the user keeps dragging
/// the window after it is tracked, and a delta follows that edit instead of
/// throwing it away.
struct MaskKeyframe: Equatable, Codable, Sendable {
    /// Project time, in seconds.
    var time: Double
    /// Normalized translation from the authored position.
    var offsetX: Double
    var offsetY: Double
    /// Multiplier on the authored size. 1 is "the same size it was drawn".
    var scale: Double

    init(time: Double, offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1) {
        self.time = time
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    static let identity = MaskKeyframe(time: 0)
}

/// One window's path across a shot.
///
/// What this is **not**: Resolve's planar tracker, which solves rotation,
/// perspective and shear off a patch of texture. Vision's object tracker
/// returns an axis-aligned box, so what can be honestly recovered from it is
/// position and size. A window that needs to roll with the camera is a window
/// this cannot follow, and the panel says so rather than producing a track
/// that is subtly wrong.
struct MaskTrack: Equatable, Codable, Sendable, Identifiable {
    var id: UUID { maskID }
    /// The window this follows.
    var maskID: UUID
    /// Sorted by time, one per sampled frame.
    var keyframes: [MaskKeyframe]

    /// Where the window is at `time`, interpolated between the two samples
    /// either side of it and held flat outside the tracked range — a window
    /// does not snap back to its drawn position the frame after the track
    /// ends.
    func keyframe(at time: Double) -> MaskKeyframe {
        guard let first = keyframes.first else { return .identity }
        guard let last = keyframes.last, keyframes.count > 1 else { return first }
        if time <= first.time { return first }
        if time >= last.time { return last }

        // Sorted, so a binary search finds the pair; the sample count is one
        // per frame of a shot, which is thousands on a long one.
        var low = 0
        var high = keyframes.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if keyframes[middle].time <= time { low = middle } else { high = middle }
        }
        let a = keyframes[low]
        let b = keyframes[high]
        let span = b.time - a.time
        guard span > 0 else { return a }
        let t = (time - a.time) / span
        return MaskKeyframe(
            time: time,
            offsetX: a.offsetX + (b.offsetX - a.offsetX) * t,
            offsetY: a.offsetY + (b.offsetY - a.offsetY) * t,
            scale: a.scale + (b.scale - a.scale) * t
        )
    }

    var timeRange: ClosedRange<Double>? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        return first.time...max(first.time, last.time)
    }
}

/// Applying a track to the geometry of a window.
///
/// Pure, and separate from the renderer, because this is the part that has to
/// be right: an off-by-one in the direction of the offset produces a window
/// that runs away from the thing it is following, which looks like a tracking
/// failure and is arithmetic.
enum MaskTrackMath {
    /// Which windows a track means anything for.
    ///
    /// A luminance or colour qualifier has no position — it selects by value,
    /// everywhere in the frame at once — so there is nothing for a tracker to
    /// move. Offering the button there would be a control that does nothing.
    static func isTrackable(_ kind: PhotoMaskComponentKind) -> Bool {
        kind == .radialGradient || kind == .linearGradient
    }

    /// The mask with its geometry moved to where the track says it is.
    static func tracked(_ mask: PhotoMask, by keyframe: MaskKeyframe) -> PhotoMask {
        guard keyframe != .identity || keyframe.scale != 1 else { return mask }
        var moved = mask
        for index in moved.components.indices {
            moved.components[index] = tracked(moved.components[index], by: keyframe)
        }
        return moved
    }

    static func tracked(
        _ component: PhotoMaskComponent,
        by keyframe: MaskKeyframe
    ) -> PhotoMaskComponent {
        var moved = component
        switch component.kind {
        case .radialGradient:
            moved.center = NormalizedPoint(
                x: clamp(component.center.x + keyframe.offsetX),
                y: clamp(component.center.y + keyframe.offsetY)
            )
            // Size follows the box the tracker returned, so a face walking
            // towards the camera keeps its window rather than growing out of
            // it. Clamped off zero: a radius of nothing is a window that
            // grades a single pixel.
            moved.radiusX = max(0.005, component.radiusX * keyframe.scale)
            moved.radiusY = max(0.005, component.radiusY * keyframe.scale)
        case .linearGradient:
            // A linear window has no centre, so it scales about the midpoint
            // of its two handles — which is the only point on it that means
            // anything.
            let midX = (component.startPoint.x + component.endPoint.x) / 2
            let midY = (component.startPoint.y + component.endPoint.y) / 2
            moved.startPoint = scaled(
                component.startPoint, about: (midX, midY), by: keyframe
            )
            moved.endPoint = scaled(
                component.endPoint, about: (midX, midY), by: keyframe
            )
        default:
            break
        }
        return moved
    }

    private static func scaled(
        _ point: NormalizedPoint,
        about mid: (x: Double, y: Double),
        by keyframe: MaskKeyframe
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: clamp(mid.x + (point.x - mid.x) * keyframe.scale + keyframe.offsetX),
            y: clamp(mid.y + (point.y - mid.y) * keyframe.scale + keyframe.offsetY)
        )
    }

    /// Normalized coordinates can go outside 0…1 while a window is partly off
    /// frame, but not far — a handle at 40 is a bug, not a composition.
    private static func clamp(_ value: Double) -> Double {
        min(2, max(-1, value))
    }
}
