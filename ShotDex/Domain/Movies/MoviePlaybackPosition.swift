import Foundation

/// Where a movie picks up and when it counts as seen (FS-23.02 §2).
enum MoviePlaybackPosition {
    /// Under a minute in, starting again costs nothing.
    static let minimumResumeMs: Int64 = 60_000
    /// From 95% on, the credits are rolling: the movie is watched.
    static let watchedFraction = 0.95
    /// How often the position is written while playing.
    static let saveIntervalMs: Int64 = 10_000

    /// The place to open at, or nil to start from the top. An unknown length
    /// does not block a resume; the 95% check waits until it is known.
    static func resumeMs(saved positionMs: Int64, durationMs: Int64) -> Int64? {
        guard positionMs > minimumResumeMs else { return nil }
        guard durationMs > 0 else { return positionMs }
        return isWatched(positionMs: positionMs, durationMs: durationMs) ? nil : positionMs
    }

    static func isWatched(positionMs: Int64, durationMs: Int64) -> Bool {
        durationMs > 0 && Double(positionMs) >= Double(durationMs) * watchedFraction
    }
}
