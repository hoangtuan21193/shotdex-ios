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

    /// ⌘− stops here (FS-12.17b §3): 20 pt/s, a touch above the pinch's
    /// floor, which only the Duo cover's multi-select reaches.
    static let keyboardFloor: CGFloat = 20

    /// ⌘+ / ⌘− (FS-12.17b §3): the zoom doubled or halved, inside
    /// `keyboardFloor…ceiling`. The timeline keeps the playhead where it is
    /// on screen, so the step is "around the playhead" by construction.
    static func keyboardStep(_ pps: CGFloat, zoomsIn: Bool, ceiling: CGFloat) -> CGFloat {
        let target = zoomsIn ? pps * 2 : pps / 2
        guard target.isFinite else { return keyboardFloor }
        return min(max(target, keyboardFloor), max(keyboardFloor, ceiling))
    }

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

    /// A scrub at Frame zoom (§6): how many frames the playhead has moved
    /// since the drag began — 12pt each — rounded to the nearest frame.
    static func scrubFrames(from start: Double, to time: Double, fps: Int) -> Int {
        VideoFrameGrid(fps: fps).frameCount(from: start, to: time)
    }

    /// How many frame lines lie between two playhead times — one haptic
    /// each (§6).
    static func framesCrossed(from a: Double, to b: Double, fps: Int) -> Int {
        let grid = VideoFrameGrid(fps: fps)
        return abs(grid.nearestFrame(to: b) - grid.nearestFrame(to: a))
    }

    /// The badge over the finger while scrubbing at Frame zoom: "−3 f ·
    /// 0:08.80" — the frames since the drag began, then the time.
    static func scrubBadge(frames: Int, time: Double) -> String {
        let sign = frames < 0 ? "−" : (frames > 0 ? "+" : "")
        return "\(sign)\(abs(frames)) f · " + VideoFrameGrid.hundredths(time)
    }

    /// Where a scroll at Frame zoom comes to rest: the content offset of
    /// the nearest frame line under the playhead.
    static func restingOffset(_ offset: CGFloat, inset: CGFloat, pps: CGFloat, fps: Int) -> CGFloat {
        guard pps > 0 else { return offset }
        let grid = VideoFrameGrid(fps: fps)
        let time = grid.snapped(Double((offset + inset) / pps))
        return CGFloat(time) * pps - inset
    }

    /// The ruler's label for frame `index` at Frame zoom: "8:12f" — the
    /// second, then the frame inside it.
    static func rulerFrameLabel(frame index: Int, fps: Int) -> String {
        let rate = max(1, fps)
        return String(format: "%d:%02df", index / rate, index % rate)
    }
}
