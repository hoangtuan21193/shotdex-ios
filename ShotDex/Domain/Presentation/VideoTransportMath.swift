import Foundation

/// Pure arithmetic behind the video transport: seek clamping, slider range, and
/// exported-frame filenames.
///
/// Why this is a type and not inline view code: the viewer has no UI tests, and
/// every one of these values has an edge case that produced a real bug —
/// PhotoKit hands out iCloud items whose `duration` is still `indefinite`
/// (non-finite), a `nominalFrameRate` of `0` for tracks that have not loaded,
/// and the transport must never hand `Slider` a value outside its own range or
/// `AVPlayer` a negative time. Keeping it here makes all of that testable.
enum VideoTransportMath {
    /// Frame rate assumed when the video track has not resolved one yet. Only
    /// the exported frame's filename depends on it.
    static let fallbackFrameRate: Double = 30

    /// An absolute position brought inside the clip.
    ///
    /// A non-finite or non-positive `duration` means AVFoundation has not
    /// resolved it yet; the clip length is then unknown, so only the lower
    /// bound can be enforced.
    static func clamped(seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        guard duration.isFinite, duration > 0 else { return seconds }
        return min(seconds, duration)
    }

    /// Result of a relative seek (double-tap ±10 s), clamped into the clip.
    static func seekTarget(current: Double, duration: Double, delta: Double) -> Double {
        let start = current.isFinite ? current : 0
        return clamped(seconds: start + delta, duration: duration)
    }

    /// Upper bound for the scrubber's range.
    ///
    /// `Slider` traps when its bound value falls outside `in:`, and the bound
    /// value leads `duration` in two situations: an iCloud item that is playing
    /// before its duration resolves, and a scrub in progress. The floor keeps
    /// the range non-empty.
    static func timelineUpperBound(duration: Double, current: Double, scrub: Double) -> Double {
        let candidates = [duration, current, scrub].filter { $0.isFinite }
        return max(0.1, candidates.max() ?? 0.1)
    }

    /// Remaining time, for the trailing transport label. Non-finite or
    /// unresolved durations yield `nil` so the label can stay blank rather than
    /// show a wrong number.
    static func remainingSeconds(current: Double, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, current.isFinite else { return nil }
        return max(0, duration - current)
    }

    /// Filename for a frame exported to the photo library:
    /// `IMG_4021-00-07-12.heic` — minutes, seconds, and frame number inside the
    /// second, so two grabs from the same second never collide.
    ///
    /// `base` is the clip's original filename; its extension is dropped.
    static func frameFilename(
        base: String?,
        seconds: Double,
        frameRate: Double,
        fileExtension: String
    ) -> String {
        let stem: String = {
            guard let base, !base.isEmpty else { return "Frame" }
            let trimmed = (base as NSString).deletingPathExtension
            return trimmed.isEmpty ? "Frame" : trimmed
        }()
        let time = seconds.isFinite && seconds > 0 ? seconds : 0
        let rate = frameRate.isFinite && frameRate > 0 ? frameRate : fallbackFrameRate
        let whole = Int(time)
        let minutes = whole / 60
        let secs = whole % 60
        // Frame index inside the current second, clamped so a rounding artifact
        // at the second boundary cannot produce e.g. frame 30 of a 30 fps clip.
        let frame = min(Int((time - Double(whole)) * rate), max(0, Int(rate.rounded()) - 1))
        return String(format: "%@-%02d-%02d-%02d.%@", stem, minutes, secs, frame, fileExtension)
    }
}
