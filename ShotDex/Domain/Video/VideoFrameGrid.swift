import Foundation

/// The project's frame grid (FS-12.17 §5, FS-12.17b §3): one frame is one
/// frame of the **project** — the frame rate of Video Settings (24, 30 or
/// 60), counted on timeline time. Every frame step in the studio lands on
/// it: ⇧← / ⇧→, Back / Forward a Frame, ±1 Frame of the frame trim, a
/// scrub at Frame zoom.
struct VideoFrameGrid: Equatable, Sendable {
    let fps: Int

    init(fps: Int) {
        self.fps = max(1, fps)
    }

    init(_ rate: VideoFrameRate) {
        self.init(fps: rate.rawValue)
    }

    /// One frame, in seconds.
    var frameDuration: Double { 1 / Double(fps) }

    /// How near a frame line a time has to be to count as on it — far
    /// under a frame, far over a `Double`'s noise after a few additions.
    private static let onGridTolerance = 1e-4

    /// The time in frames, unrounded.
    func frames(at time: Double) -> Double { time * Double(fps) }

    /// The frame line nearest `time`.
    func nearestFrame(to time: Double) -> Int { Int(frames(at: time).rounded()) }

    func time(ofFrame index: Int) -> Double { Double(index) / Double(fps) }

    /// `time` moved to the nearest frame line.
    func snapped(_ time: Double) -> Double { self.time(ofFrame: nearestFrame(to: time)) }

    /// Whether `time` sits on a frame line.
    func isOnGrid(_ time: Double) -> Bool {
        abs(frames(at: time) - frames(at: time).rounded()) < Self.onGridTolerance
    }

    /// `time` stepped `count` frames — negative is earlier. From a time on
    /// the grid every step is one frame; from a time between two lines the
    /// first step goes to the next line in that direction, so a step never
    /// leaves the playhead off the grid it is meant to walk.
    func step(from time: Double, by count: Int) -> Double {
        guard count != 0 else { return time }
        let position = frames(at: time)
        if isOnGrid(time) {
            return self.time(ofFrame: Int(position.rounded()) + count)
        }
        let first = count > 0 ? Int(position.rounded(.up)) : Int(position.rounded(.down))
        let rest = count > 0 ? count - 1 : count + 1
        return self.time(ofFrame: first + rest)
    }

    /// How many frames lie between two times, rounded to the nearest
    /// whole frame — "−4 frames".
    func frameCount(from start: Double, to end: Double) -> Int {
        Int(((end - start) * Double(fps)).rounded())
    }

    /// `m:ss.cc` — minutes, seconds and hundredths, rounded: "0:09.07" for
    /// 9.0667 s. The read-out of a frame edit, where tenths cannot tell two
    /// frames apart.
    static func hundredths(_ seconds: Double) -> String {
        let total = Int((max(0, seconds) * 100).rounded())
        let minutes = total / 6000
        let secs = (total / 100) % 60
        let cents = total % 100
        return String(format: "%d:%02d.%02d", minutes, secs, cents)
    }
}
