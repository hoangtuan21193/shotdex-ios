import Foundation

/// FS-19.08 §6d: Compare plays the two copies of a Same video as one — the
/// left copy leads (and alone has sound), the right one follows. The
/// follower is put back on the leader's time when they drift apart by more
/// than two frames (never under 50 ms, so main-thread jitter is not drift);
/// a seek both make together lands both there.
enum CommonPhotosVideoSync {
    /// One frame at this rate; 30 fps when the file does not say.
    static func frameDuration(fps: Float) -> Double {
        fps > 0 ? 1 / Double(fps) : 1.0 / 30
    }

    /// Whether the follower is off the leader by more than the tolerance.
    static func needsSeek(leader: Double, follower: Double, frameDuration: Double) -> Bool {
        abs(leader - follower) > tolerance(frameDuration: frameDuration)
    }

    /// Two frames, at least 50 ms.
    static func tolerance(frameDuration: Double) -> Double {
        max(2 * frameDuration, 0.05)
    }

    /// The playhead is on the last frame: Play starts from 0 again.
    static func isAtEnd(time: Double, duration: Double, frameDuration: Double) -> Bool {
        duration > 0 && time >= duration - frameDuration
    }

    /// Where a scrub to `fraction` of `duration` takes both, clamped.
    static func time(at fraction: Double, of duration: Double) -> Double {
        max(0, min(1, fraction)) * max(0, duration)
    }

    /// "0:06" for the time shown under the scrubber; hours when it has them.
    static func label(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        let (h, m, s) = (whole / 3600, whole / 60 % 60, whole % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
