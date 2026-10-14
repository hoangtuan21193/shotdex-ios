import Foundation

/// Which cues of one subtitle are on screen at a movie time, with the
/// panel's Sync applied (FS-23.03 §2): Sync +2.0 s shows a cue timed
/// `00:01:05,000` at movie time 1:07.0 — for subtitles that run early.
struct SubtitleTimeline: Sendable {
    let document: SubtitleDocument
    var delayMs: Int64
    /// The longest cue, so a lookup only scans cues that could still be on.
    private let longestMs: Int64
    private let starts: [Int64]

    init(document: SubtitleDocument, delayMs: Int64 = 0) {
        self.document = document
        self.delayMs = delayMs
        longestMs = document.cues.map { $0.endMs - $0.startMs }.max() ?? 0
        starts = document.cues.map(\.startMs)
    }

    /// In start order; overlapping cues all show (FS-23.03 §4).
    func cues(atMs movieTime: Int64) -> [SubtitleCue] {
        let time = movieTime - delayMs
        // First cue that starts after `time`; anything on screen is before it
        // and started no earlier than `time - longestMs`.
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= time { low = mid + 1 } else { high = mid }
        }
        var result: [SubtitleCue] = []
        var index = low - 1
        while index >= 0, starts[index] >= time - longestMs {
            let cue = document.cues[index]
            if cue.startMs <= time, time < cue.endMs { result.append(cue) }
            index -= 1
        }
        return result.reversed()
    }
}
