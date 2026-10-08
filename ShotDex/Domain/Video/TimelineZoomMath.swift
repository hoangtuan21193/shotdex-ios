import CoreGraphics
import Foundation

/// The timeline's zoom, in points per second of timeline (FS-12.17 §6,
/// FS-12.17b §3): where a pinch stops, what ⌘+ and ⌘− do, and when the
/// timeline is at **Frame zoom** — one frame of the project 12pt wide.
///
/// Pure: the timeline view keeps the live value in its own state (a pinch
/// writes it sixty times a second) and asks here for every bound.
enum TimelineZoomMath {
    /// The pinch's floor: the Duo cover's multi-select zoom (FS-12.11
    /// AC-14) is the most zoomed-out the timeline ever goes.
    static let floor: CGFloat = 18
    /// Where a pinch stops while "Frame zoom on pinch" is off — the range
    /// the timeline had before FS-12.17.
    static let standardCeiling: CGFloat = 160

    /// Frame zoom: one frame of the project 12pt wide (§6).
    static let pointsPerFrame: CGFloat = 12
    /// The ruler's labels at Frame zoom: every 6 frames, 72pt apart.
    static let framesPerRulerLabel = 6

    /// The zoom a pinch, a fit or a keyboard step asks for, held inside
    /// `floor…ceiling`.
    static func clampedPPS(_ pps: CGFloat, ceiling: CGFloat = standardCeiling) -> CGFloat {
        guard pps.isFinite else { return floor }
        return min(max(pps, floor), max(floor, ceiling))
    }

    /// Frame zoom's points per second: 12pt a frame — 360 at 30 fps, 288 at
    /// 24, 720 at 60.
    static func frameZoomPPS(fps: Int) -> CGFloat {
        pointsPerFrame * CGFloat(max(1, fps))
    }

    /// Where a pinch stops: Frame zoom when "Frame zoom on pinch" is on
    /// (the default), 160 when it is off (§7).
    static func ceiling(frameZoomOnPinch: Bool, fps: Int) -> CGFloat {
        frameZoomOnPinch ? max(standardCeiling, frameZoomPPS(fps: fps)) : standardCeiling
    }

    /// Whether the timeline is at Frame zoom — the pill shows, the ruler
    /// counts frames, a scrub steps a frame per 12pt.
    static func isFrameZoom(_ pps: CGFloat, fps: Int) -> Bool {
        pps >= frameZoomPPS(fps: fps) - 0.5
    }

    /// The ruler's label for frame `index` at Frame zoom: "8:12f" — the
    /// second, then the frame inside it.
    static func rulerFrameLabel(frame index: Int, fps: Int) -> String {
        let rate = max(1, fps)
        return String(format: "%d:%02df", index / rate, index % rate)
    }
}
