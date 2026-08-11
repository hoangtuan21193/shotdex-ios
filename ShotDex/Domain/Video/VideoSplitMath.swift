import Foundation

/// Splits one clip into two at a timeline-local time. Pure so the split point
/// maths (source-time mapping through trim + speed) is unit-tested away from
/// the model. Returns nil when either half would fall under the minimum
/// playable length, so a split at the very edge is a no-op rather than a
/// zero-length clip.
enum VideoSplitMath {
    /// `localTime` is seconds from the clip's own start on the timeline (its
    /// effective, speed-scaled length). The two children keep the parent's
    /// effect / mute / speed; each gets a fresh id.
    static func split(_ clip: VideoClip, atLocalTime localTime: Double) -> (VideoClip, VideoClip)? {
        let total = clip.effectiveDuration
        guard localTime > 0, localTime < total else { return nil }

        switch clip.kind {
        case .photo, .freeze:
            let firstDuration = localTime
            let secondDuration = total - localTime
            guard firstDuration >= minimum, secondDuration >= minimum else { return nil }
            var first = copy(clip)
            var second = copy(clip)
            first.photoDuration = firstDuration
            second.photoDuration = secondDuration
            return (first, second)

        case .video:
            let sourceDuration = clip.sourceDuration ?? 0
            let trimEnd = clip.trimEnd ?? sourceDuration
            // Timeline-local time → source time: the finger is on the scaled
            // timeline, the trim window is in source seconds.
            let sourceSplit = clip.trimStart + localTime * max(clip.speed, VideoClip.speedRange.lowerBound)
            let firstSourceLength = sourceSplit - clip.trimStart
            let secondSourceLength = trimEnd - sourceSplit
            guard firstSourceLength >= minimum, secondSourceLength >= minimum,
                  sourceSplit > clip.trimStart, sourceSplit < trimEnd
            else { return nil }
            var first = copy(clip)
            var second = copy(clip)
            first.trimStart = clip.trimStart
            first.trimEnd = sourceSplit
            second.trimStart = sourceSplit
            second.trimEnd = trimEnd
            return (first, second)
        }
    }

    private static let minimum = VideoClip.minimumClipDuration

    /// A same-media, same-settings clip with a fresh identity.
    private static func copy(_ clip: VideoClip) -> VideoClip {
        var new = VideoClip(assetID: clip.assetID, kind: clip.kind)
        new.photoDuration = clip.photoDuration
        new.trimStart = clip.trimStart
        new.trimEnd = clip.trimEnd
        new.isMuted = clip.isMuted
        new.effect = clip.effect
        new.speed = clip.speed
        new.freezeSourceTime = clip.freezeSourceTime
        new.sourceDuration = clip.sourceDuration
        return new
    }
}
