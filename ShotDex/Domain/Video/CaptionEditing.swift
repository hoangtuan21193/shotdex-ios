import Foundation

/// Split, Merge, Delete and typing on caption cues (FS-12.14 §5). Pure: the
/// model wraps each in one undo step.
enum CaptionEditing {
    /// A cue shorter than this is not made by a split.
    static let shortestCue: Double = 0.1

    /// The cue split at source second `time` (the playhead): the times part
    /// at the playhead, the words at the word boundary nearest it — "starts
    /// right here." at 6.7 s between "right" and "here." is "starts right"
    /// 6.0–6.7 and "here." 6.7–7.4. Nil when the playhead is not inside the
    /// cue, or a side would have no word.
    static func split(_ cue: CaptionCue, atSource time: Double) -> (CaptionCue, CaptionCue)? {
        guard time > cue.sourceStart + shortestCue, time < cue.sourceEnd - shortestCue else { return nil }
        let words = cue.words ?? evenWords(cue)
        guard words.count >= 2 else { return nil }
        // The boundary nearest the playhead: between word i-1 and word i.
        var best = 1
        var bestDistance = Double.infinity
        for index in 1..<words.count {
            let boundary = (words[index - 1].end + words[index].start) / 2
            let distance = abs(boundary - time)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        let first = Array(words[..<best])
        let second = Array(words[best...])
        let keepsTimes = cue.words != nil
        let left = CaptionCue(
            clipID: cue.clipID, sourceStart: cue.sourceStart, sourceEnd: time,
            text: first.map(\.text).joined(separator: " "),
            words: keepsTimes ? first : nil, isEdited: cue.isEdited
        )
        let right = CaptionCue(
            clipID: cue.clipID, sourceStart: time, sourceEnd: cue.sourceEnd,
            text: second.map(\.text).joined(separator: " "),
            words: keepsTimes ? second : nil, isEdited: cue.isEdited
        )
        return (left, right)
    }

    /// The cue joined with the one after it (§5): the words with one space,
    /// the time the union of the two. Both from the same clip — a cue is
    /// anchored to one clip, and a line across a cut would follow neither.
    static func merge(_ first: CaptionCue, _ second: CaptionCue) -> CaptionCue? {
        guard first.clipID == second.clipID else { return nil }
        let words: [CaptionWord]? = if let a = first.words, let b = second.words { a + b } else { nil }
        return CaptionCue(
            id: first.id,
            clipID: first.clipID,
            sourceStart: min(first.sourceStart, second.sourceStart),
            sourceEnd: max(first.sourceEnd, second.sourceEnd),
            text: [first.text, second.text].filter { !$0.isEmpty }.joined(separator: " "),
            words: words,
            isEdited: first.isEdited || second.isEdited
        )
    }

    /// The cue that plays right after `cueID` in the lane, if any.
    static func next(after cueID: UUID, in placed: [CaptionTimeline.Placed]) -> CaptionTimeline.Placed? {
        guard let index = placed.firstIndex(where: { $0.cue.id == cueID }), index + 1 < placed.count else { return nil }
        return placed[index + 1]
    }

    /// Typed text: the cue is edited by hand, its word times are gone.
    static func editing(_ cue: CaptionCue, text: String) -> CaptionCue {
        var edited = cue
        edited.text = text
        if text != cue.text {
            edited.isEdited = true
            edited.words = nil
        }
        return edited
    }

    /// The words of a cue spread evenly over its time — Word by Word on a
    /// cue whose times were lost to typing (§5).
    static func evenWords(_ cue: CaptionCue) -> [CaptionWord] {
        let parts = cue.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return [] }
        let step = cue.sourceDuration / Double(parts.count)
        return parts.enumerated().map { index, text in
            CaptionWord(text: text, start: cue.sourceStart + Double(index) * step, end: cue.sourceStart + Double(index + 1) * step)
        }
    }
}
