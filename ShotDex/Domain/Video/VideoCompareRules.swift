import CoreGraphics
import Foundation

/// FS-24 §10: the pure rules behind Compare Videos — which files are in it,
/// how B is kept on A's clock, and the Mac's shared zoom.
enum VideoCompareRules {
    /// One file of the batch that has a compressed copy to hold its original against.
    struct Pair: Equatable, Identifiable, Sendable {
        /// The original's identifier — the batch item's id.
        let id: String
        let copyID: String
        let originalBytes: Int64
        let copyBytes: Int64

        /// 0…1: how much smaller the copy is.
        var reduction: Double {
            guard originalBytes > 0 else { return 0 }
            return max(0, 1 - Double(copyBytes) / Double(originalBytes))
        }

        var savedBytes: Int64 { max(0, originalBytes - copyBytes) }
    }

    /// Where stepping by `step` from `current` lands; nil when there is
    /// nowhere to go. Stepping does not wrap: `Video 4 of 4 ›` is the end.
    static func index(after current: Int, step: Int, count: Int) -> Int? {
        let next = current + step
        guard count > 0, next >= 0, next < count else { return nil }
        return next
    }

    /// The pair to show after the current one leaves (its original was
    /// deleted): the one that took its place, or the new last one.
    static func index(afterRemoving removed: Int, remaining: Int) -> Int? {
        guard remaining > 0 else { return nil }
        return min(removed, remaining - 1)
    }

    // MARK: Time sync (AC-24.17)

    /// How far B may drift from A before it is moved back. Paused, the two
    /// must show the same frame, so anything past half a frame is a seek;
    /// playing, a seek costs a stutter, so B is left alone within one frame.
    static func needsResync(drift seconds: Double, frameRate: Double, isPlaying: Bool) -> Bool {
        let frame = 1 / max(frameRate, 1)
        let limit = isPlaying ? frame : frame / 2
        return abs(seconds) > limit
    }

    // MARK: Zoom (Mac; iOS uses `CompareScrollSynchronizer`)

    static let minimumZoom: CGFloat = 1
    static let maximumZoom: CGFloat = 8
    /// What a double-tap zooms to from fit (FS-24 §10).
    static let doubleTapZoom: CGFloat = 3

    /// The offset that keeps `point` (in the pane, from its centre) under the
    /// finger as the scale goes from `scale` to `newScale`, clamped so the
    /// frame still covers the pane.
    static func zoom(scale: CGFloat, offset: CGSize, to newScale: CGFloat,
                     about point: CGPoint, paneSize: CGSize) -> (scale: CGFloat, offset: CGSize) {
        let clamped = min(max(newScale, minimumZoom), maximumZoom)
        let ratio = clamped / max(scale, 0.0001)
        let moved = CGSize(
            width: point.x - (point.x - offset.width) * ratio,
            height: point.y - (point.y - offset.height) * ratio
        )
        return (clamped, clampedOffset(moved, scale: clamped, paneSize: paneSize))
    }

    /// Pans no further than the scaled frame's edge; at fit, no offset.
    static func clampedOffset(_ offset: CGSize, scale: CGFloat, paneSize: CGSize) -> CGSize {
        let maxX = max(0, (paneSize.width * scale - paneSize.width) / 2)
        let maxY = max(0, (paneSize.height * scale - paneSize.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }
}
