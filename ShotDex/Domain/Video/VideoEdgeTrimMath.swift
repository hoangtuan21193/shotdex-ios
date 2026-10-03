import Foundation

/// Cutting a clip by dragging one of its edges on the timeline (FS-12.05 §3).
///
/// The drag arrives in **timeline** seconds — how far the finger moved, over
/// the zoom. A video turns that into a move of its source window through its
/// speed (one timeline second of a 2× clip is two source seconds); a photo
/// or a freeze turns it into a new length on screen. Either way the result
/// is clamped — to the source's own ends, to a clip's minimum, to a still's
/// 0.5–10 s — and says whether it hit the limit, which is when the finger
/// feels a tick.
enum VideoEdgeTrimMath {
    enum Edge: Equatable, Sendable { case leading, trailing }

    struct Result: Equatable, Sendable {
        /// Video: the new source window.
        var trimStart: Double
        var trimEnd: Double?
        /// Photo and freeze: the new length on screen.
        var photoDuration: Double
        /// The clip's new length on the timeline.
        var duration: Double
        /// The drag ran into a limit and was stopped there.
        var hitLimit: Bool
    }

    /// The clip after dragging `edge` by `delta` timeline seconds — positive
    /// is rightwards, so a leading edge dragged right and a trailing edge
    /// dragged left both shorten the clip.
    static func drag(_ clip: VideoClip, edge: Edge, by delta: Double) -> Result {
        switch clip.kind {
        case .photo, .freeze:
            let range = VideoClip.photoDurationRange
            let wanted = edge == .leading ? clip.photoDuration - delta : clip.photoDuration + delta
            let clamped = min(max(wanted, range.lowerBound), range.upperBound)
            return Result(
                trimStart: clip.trimStart, trimEnd: clip.trimEnd,
                photoDuration: clamped, duration: clamped,
                hitLimit: abs(clamped - wanted) > 0.000_001
            )
        case .video:
            let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
            let minimumSource = VideoClip.minimumClipDuration * speed
            let sourceDelta = delta * speed
            let start = clip.trimStart
            let end = clip.trimEnd ?? clip.sourceDuration ?? start
            var newStart = start
            var newEnd = end
            var hitLimit = false
            // A source whose length is not known yet (an iCloud original)
            // can only be cut inwards: there is nothing known past its edges.
            let known = clip.sourceDuration
            switch edge {
            case .leading:
                let floor = known == nil ? start : 0
                let ceiling = end - minimumSource
                let wanted = start + sourceDelta
                newStart = min(max(wanted, floor), ceiling)
                hitLimit = abs(newStart - wanted) > 0.000_001
            case .trailing:
                let floor = start + minimumSource
                let ceiling = known ?? end
                let wanted = end + sourceDelta
                newEnd = min(max(wanted, floor), ceiling)
                hitLimit = abs(newEnd - wanted) > 0.000_001
            }
            return Result(
                trimStart: newStart, trimEnd: newEnd,
                photoDuration: clip.photoDuration,
                duration: max(VideoClip.minimumClipDuration, (newEnd - newStart) / speed),
                hitLimit: hitLimit
            )
        }
    }

    /// The timeline time of the dragged edge after a drag of `delta`, for a
    /// clip placed at `start` lasting `duration` — what snapping compares
    /// against the playhead, markers and other clips' edges.
    static func edgeTime(edge: Edge, start: Double, duration: Double, delta: Double) -> Double {
        edge == .leading ? start + delta : start + duration + delta
    }
}
