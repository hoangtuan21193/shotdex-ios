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

    /// The zoom a pinch, a fit or a keyboard step asks for, held inside
    /// `floor…ceiling`.
    static func clampedPPS(_ pps: CGFloat, ceiling: CGFloat = standardCeiling) -> CGFloat {
        guard pps.isFinite else { return floor }
        return min(max(pps, floor), max(floor, ceiling))
    }
}
