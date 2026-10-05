import Foundation

/// Recognised words into caption blocks (FS-12.14 §4): one line of at most
/// 32 characters and at most 3.0 s, broken at a pause of 0.4 s or more, or
/// after punctuation. Pure, so the one rule both the burnt-in captions and
/// the subtitle track use is tested on its own (§6).
enum CaptionChunker {
    static let maximumCharacters = 32
    static let maximumDuration: Double = 3.0
    static let pauseBreak: Double = 0.4

    /// Cues for the words of one clip, in time order. Words keep the source
    /// times they were heard at; each cue starts at its first word and ends
    /// at its last.
    static func cues(from words: [CaptionWord], clipID: UUID) -> [CaptionCue] {
        let words = words
            .map { CaptionWord(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), start: $0.start, end: max($0.start, $0.end)) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
        var cues: [CaptionCue] = []
        var current: [CaptionWord] = []

        func close() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(CaptionCue(
                clipID: clipID,
                sourceStart: first.start,
                sourceEnd: last.end,
                text: current.map(\.text).joined(separator: " "),
                words: current
            ))
            current = []
        }

        for word in words {
            if let first = current.first, let previous = current.last {
                let text = (current.map(\.text) + [word.text]).joined(separator: " ")
                let breaks = word.start - previous.end >= pauseBreak - 1e-9
                    || endsSentence(previous.text)
                    || text.count > maximumCharacters
                    || word.end - first.start > maximumDuration + 1e-9
                if breaks { close() }
            }
            current.append(word)
        }
        close()
        return cues
    }

    /// Punctuation a line breaks after.
    static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ".,!?;:…。、！？".contains(last)
    }

    /// "Caption 1", "Caption 2"… in the order the cues play.
    static func name(at index: Int) -> String {
        String(
            localized: "Caption \(index + 1)",
            table: "VideoStudio",
            comment: "Video Studio captions: a caption block, by its place in time order — Caption 2"
        )
    }
}
