import Foundation

/// The movie time a subtitle frame should show. VLC reports its time a few
/// times a second; between reports the clock runs on the host clock at the
/// playback rate, so cues change on the frame they are due (FS-23 plan risk
/// "phụ đề lệch giờ").
///
/// Small differences between a report and the running clock are folded in
/// gradually and never make time go backwards while playing; a jump (seek,
/// or a report far from the clock) re-anchors at once.
struct PlaybackClock: Sendable {
    /// A report this far from the running clock is a jump, not drift.
    static let jumpMs: Double = 250
    /// Share of the drift folded in per report.
    static let correction = 0.25

    private(set) var isRunning = false
    private(set) var rate: Double = 1
    private var anchorMs: Double = 0
    private var anchorHost: TimeInterval = 0
    /// Last value handed out while running — the floor for the next.
    private var lastShownMs: Double = 0

    /// The time to draw at `host` (seconds on a monotonic clock).
    mutating func timeMs(at host: TimeInterval) -> Int64 {
        var now = anchorMs
        if isRunning { now += max(0, host - anchorHost) * 1000 * rate }
        if isRunning { now = max(now, lastShownMs) }
        lastShownMs = now
        return Int64(now.rounded())
    }

    /// The player said where it is.
    mutating func report(_ reportedMs: Int64, at host: TimeInterval) {
        let predicted = predictedMs(at: host)
        let reported = Double(reportedMs)
        if !isRunning || abs(reported - predicted) > Self.jumpMs {
            anchor(reported, at: host)
            lastShownMs = reported
            return
        }
        // Drift: move part of the way, but not below what was shown.
        anchor(max(predicted + (reported - predicted) * Self.correction, lastShownMs), at: host)
    }

    /// Play, pause, or stall for buffering (`running: false`).
    mutating func setRunning(_ running: Bool, at host: TimeInterval) {
        guard running != isRunning else { return }
        anchor(predictedMs(at: host), at: host)
        isRunning = running
    }

    mutating func setRate(_ newRate: Double, at host: TimeInterval) {
        anchor(predictedMs(at: host), at: host)
        rate = newRate
    }

    /// The user moved the playhead: show that time now, forwards or back.
    mutating func seek(to ms: Int64, at host: TimeInterval) {
        anchor(Double(ms), at: host)
        lastShownMs = Double(ms)
    }

    private func predictedMs(at host: TimeInterval) -> Double {
        isRunning ? anchorMs + max(0, host - anchorHost) * 1000 * rate : anchorMs
    }

    private mutating func anchor(_ ms: Double, at host: TimeInterval) {
        anchorMs = ms
        anchorHost = host
    }
}
