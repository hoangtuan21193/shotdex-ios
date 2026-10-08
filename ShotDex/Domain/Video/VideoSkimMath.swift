import Foundation

/// Skimming a library video with the pointer (FS-12.17b §6, board
/// F6_IL_HoverScrub): where across the cell the pointer is says which
/// moment of the source the viewer shows — 46% of 0:05 is 0:02.3.
enum VideoSkimMath {
    /// How often a new frame is asked for: thirty a second at most.
    static let minimumInterval: TimeInterval = 1.0 / 30

    /// The source time under the pointer: `fraction` of the way across a
    /// cell of a `duration`-long video, held inside it.
    static func time(fraction: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, fraction.isFinite else { return 0 }
        let time = min(max(0, fraction), 1) * duration
        // Tenths, as the header shows them: 0.46 × 5 is 2.3, not 2.3000000000000003.
        return (time * 10).rounded() / 10
    }

    /// "0:02.3" — minutes, seconds and a tenth.
    static func timeLabel(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    /// "0:05" — a video's length, whole seconds.
    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// What follows "Skimming" under the frame: "· Lake · 0:02.3 / 0:05"
    /// for a video, "· Lake" for a photo, with "· Not downloaded" when the
    /// source is only in iCloud and the viewer shows its thumbnail.
    static func detail(name: String, time: Double?, duration: Double?, notDownloaded: Bool, notDownloadedText: String) -> String {
        var parts = ["· " + name]
        if let time, let duration {
            parts.append("· " + timeLabel(time) + " / " + durationLabel(duration))
        }
        if notDownloaded { parts.append("· " + notDownloadedText) }
        return parts.joined(separator: " ")
    }

    /// Paces the frame requests while the pointer moves (§6): one at most
    /// every thirtieth of a second, and only ever the newest — a position
    /// the pointer has already left is never decoded.
    struct Throttle: Equatable {
        private(set) var lastRequest: TimeInterval?
        /// The newest position waiting for its turn.
        private(set) var pending: Double?

        /// The pointer is at `time` now (`clock` seconds): returns the time
        /// to ask for, or nil when it must wait — then it is kept as the
        /// pending one, replacing any older.
        mutating func offer(_ time: Double, at clock: TimeInterval) -> Double? {
            if let last = lastRequest, clock - last < VideoSkimMath.minimumInterval - 1e-9 {
                pending = time
                return nil
            }
            lastRequest = clock
            pending = nil
            return time
        }

        /// A tick at `clock`: the pending position, once its turn has come.
        mutating func flush(at clock: TimeInterval) -> Double? {
            guard let pending else { return nil }
            if let last = lastRequest, clock - last < VideoSkimMath.minimumInterval - 1e-9 { return nil }
            lastRequest = clock
            self.pending = nil
            return pending
        }

        /// The pointer left: nothing is waiting any more.
        mutating func reset() {
            lastRequest = nil
            pending = nil
        }
    }
}
