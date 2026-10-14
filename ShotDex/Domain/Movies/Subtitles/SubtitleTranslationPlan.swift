import Foundation

/// How a subtitle is cut up for an AI and put back together (FS-23.04 §2):
/// blocks of numbered cues with five cues before as context, the cue count
/// kept, and **the timing never written by the AI** — every translated cue
/// takes the original's start and end.
enum SubtitleTranslationPlan {
    /// Cues sent before a block as context, not to be translated again.
    static let contextCount = 5
    /// Cues per request: home servers and cloud services.
    static let modelBlockSize = 40
    /// Apple Intelligence: a 4,096-token window, a new session per block.
    static let onDeviceBlockSize = 30
    /// A line break inside a cue, as sent and as read back.
    static let lineBreak = " ⏎ "

    /// The blocks still to do, from cue `start` on.
    static func blocks(count: Int, from start: Int, size: Int) -> [Range<Int>] {
        guard size > 0 else { return [] }
        return stride(from: max(0, start), to: count, by: size).map { $0..<min($0 + size, count) }
    }

    /// The instructions: the title, the two languages, keep the numbering
    /// and the line breaks, merge nothing, add nothing.
    static func instructions(movieTitle: String, from: String, to: String) -> String {
        """
        You translate the subtitles of the movie "\(movieTitle)" from \(from) into \(to).
        Each line you receive starts with a number and a "|". Answer with exactly one
        line per numbered input line, in the same order, starting with the same number
        and "|", then the translation. Keep "\(lineBreak.trimmingCharacters(in: .whitespaces))" where it appears: it is a line break
        inside one subtitle. Never merge or split lines, never skip one, never add notes
        or explanations. Translate sound descriptions like [music] too.
        Lines under "Context" are earlier subtitles for meaning only; do not translate them.
        """
    }

    /// The request for one block: context, then the numbered cues (numbers
    /// start at 1 within the block).
    static func prompt(cues: [SubtitleCue], block: Range<Int>) -> String {
        var lines: [String] = []
        let contextStart = max(0, block.lowerBound - contextCount)
        if contextStart < block.lowerBound {
            lines.append("Context:")
            lines += cues[contextStart..<block.lowerBound].map { "- " + text($0) }
            lines.append("")
        }
        lines.append("Translate:")
        for (offset, index) in block.enumerated() {
            lines.append("\(offset + 1)|\(text(cues[index]))")
        }
        return lines.joined(separator: "\n")
    }

    /// The translations of `block`, by cue index — nil when the answer does
    /// not have exactly one line per cue (FS-23.04 §2: retry, then cue by
    /// cue).
    static func parse(_ answer: String, block: Range<Int>) -> [Int: String]? {
        var found: [Int: String] = [:]
        for raw in answer.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let bar = line.firstIndex(of: "|"),
                  let number = Int(line[..<bar].trimmingCharacters(in: CharacterSet(charactersIn: " .)"))),
                  (1...block.count).contains(number) else { continue }
            let text = line[line.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            guard found[block.lowerBound + number - 1] == nil, !text.isEmpty else { return nil }
            found[block.lowerBound + number - 1] = untext(text)
        }
        return found.count == block.count ? found : nil
    }

    /// The translated subtitle: the original's cues, timing and placement,
    /// with the new words. A cue with no translation keeps its original.
    static func document(original: SubtitleDocument, translations: [Int: String]) -> SubtitleDocument {
        SubtitleDocument(cues: original.cues.enumerated().map { index, cue in
            guard let text = translations[index] else { return cue }
            var translated = cue
            translated.lines = text.components(separatedBy: "\n").map { [SubtitleRun(text: $0)] }
            return translated
        })
    }

    static func srt(_ document: SubtitleDocument) -> String {
        func stamp(_ ms: Int64) -> String {
            String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1_000 % 60, ms % 1_000)
        }
        return document.cues.enumerated().map { index, cue in
            "\(index + 1)\n\(stamp(cue.startMs)) --> \(stamp(cue.endMs))\n\(cue.plainText)\n"
        }.joined(separator: "\n")
    }

    private static func text(_ cue: SubtitleCue) -> String {
        cue.plainText.replacingOccurrences(of: "\n", with: lineBreak)
    }

    private static func untext(_ text: String) -> String {
        text.replacingOccurrences(of: lineBreak.trimmingCharacters(in: .whitespaces), with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
