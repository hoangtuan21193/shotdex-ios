import Foundation

/// Trim → Start to Playhead / End to Playhead (FS-12.05 §3): throw away the
/// part of a clip before the playhead, or after it. The clip keeps its place
/// on the track; everything after it closes up.
///
/// Pure: the model hands in the clip, where it sits and the playhead, and
/// applies what comes back as one undo step.
enum VideoClipTrimMath {
    enum End: Equatable, Sendable { case start, end }

    /// Why the chips cannot act right now (FS-12.05 AC-7).
    enum Unavailable: Equatable, Sendable {
        /// The playhead is outside the clip, or exactly on one of its edges:
        /// there is nothing to cut.
        case playheadOutsideClip
        /// What would be left is shorter than a clip may be.
        case tooShort
    }

    /// What the clip becomes.
    enum Outcome: Equatable, Sendable {
        /// A video: the new source window.
        case trim(start: Double, end: Double)
        /// A photo or a freeze: the new length on screen.
        case duration(Double)
        case unavailable(Unavailable)
    }

    /// Whether the chips can act for a clip placed at `clipStart` lasting
    /// `clipDuration` with the playhead at `playhead` (timeline seconds).
    static func availability(clipStart: Double, clipDuration: Double, playhead: Double) -> Unavailable? {
        let local = playhead - clipStart
        return local > 0 && local < clipDuration ? nil : .playheadOutsideClip
    }

    /// The clip after cutting `end` to the playhead, `localTime` seconds into
    /// its placement. Local time runs at the clip's speed; the source window
    /// does not, so a 2× clip 1.5 s in is 3.0 s into its source.
    static func trimToPlayhead(_ clip: VideoClip, end: End, localTime: Double) -> Outcome {
        let length = clip.effectiveDuration
        guard localTime > 0, localTime < length else { return .unavailable(.playheadOutsideClip) }
        switch clip.kind {
        case .photo, .freeze:
            let kept = end == .start ? length - localTime : localTime
            guard kept >= VideoClip.photoDurationRange.lowerBound else { return .unavailable(.tooShort) }
            return .duration(kept)
        case .video:
            guard let sourceDuration = clip.sourceDuration else { return .unavailable(.tooShort) }
            let sourceTime = clip.trimStart + localTime * max(clip.speed, VideoClip.speedRange.lowerBound)
            let start = end == .start ? sourceTime : clip.trimStart
            let finish = end == .start ? (clip.trimEnd ?? sourceDuration) : sourceTime
            guard finish - start >= VideoClip.minimumClipDuration else { return .unavailable(.tooShort) }
            let clamped = VideoTimelineMath.clampedTrim(start: start, end: finish, sourceDuration: sourceDuration)
            return .trim(start: clamped.start, end: clamped.end)
        }
    }
}
