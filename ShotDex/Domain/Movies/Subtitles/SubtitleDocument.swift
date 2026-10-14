import Foundation

/// A stretch of subtitle text with one style. Font, color, effects and
/// coordinates from the file are dropped (FS-23.03 §3); italic and bold
/// stay.
struct SubtitleRun: Equatable, Hashable, Sendable {
    var text: String
    var isItalic = false
    var isBold = false
}

/// One timed subtitle. `lines` are the visual lines, each a list of runs.
struct SubtitleCue: Equatable, Hashable, Sendable {
    enum Placement: Sendable {
        case bottom
        /// ASS `\an7…9` (or a top style), WebVTT `line:0`: kept at the top
        /// of the frame.
        case top
    }

    var startMs: Int64
    var endMs: Int64
    var lines: [[SubtitleRun]]
    var placement: Placement = .bottom

    /// The words alone, lines joined with `\n` — what Translate sends and
    /// what tests read.
    var plainText: String {
        lines.map { $0.map(\.text).joined() }.joined(separator: "\n")
    }
}

/// A parsed subtitle file: cues in start order.
struct SubtitleDocument: Equatable, Sendable {
    var cues: [SubtitleCue]

    init(cues: [SubtitleCue]) {
        self.cues = cues.enumerated()
            .sorted { $0.element.startMs != $1.element.startMs ? $0.element.startMs < $1.element.startMs : $0.offset < $1.offset }
            .map(\.element)
    }
}
