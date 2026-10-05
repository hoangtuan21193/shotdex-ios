import CoreGraphics
import Foundation

/// How a caption sits in a frame (FS-12.14 §5) — the one layout the live
/// preview and the export share, so the two never drift.
///
/// Measured against the **export frame**: the text height is a share of the
/// frame's short edge, the line's centre at 85 % · 50 % · 15 % of its
/// height. A preset's Fill crop (FS-12.16) hands in its own frame, so the
/// caption is always whole inside what is written.
enum CaptionLayout {
    static let defaultSizePercent = VideoCaptionLane.defaultSizePercent
    /// The widest a line may run, as a share of the frame's width; a longer
    /// line is set smaller, never wrapped (§4: one line).
    static let maximumLineWidth: CGFloat = 0.92
    /// Box: the dark plate behind the words (Box, Word by Word).
    static let boxOpacity: CGFloat = 0.62
    /// The plate's padding and corner, as shares of the text height — 8pt
    /// round on a 6 % caption in a 226pt-tall preview, as the board draws.
    static let boxHorizontalPadding: CGFloat = 0.38
    static let boxVerticalPadding: CGFloat = 0.22
    static let boxCornerRadius: CGFloat = 0.19

    /// The text height in the frame's pixels: ink from the top of a capital
    /// to the bottom of a descender.
    static func textHeight(frame: CGSize, sizePercent: Double) -> CGFloat {
        min(frame.width, frame.height) * CGFloat(min(max(sizePercent, VideoCaptionLane.sizeRange.lowerBound), VideoCaptionLane.sizeRange.upperBound)) / 100
    }

    /// The line's centre, y down from the frame's top.
    static func centreY(frame: CGSize, position: CaptionPosition) -> CGFloat {
        frame.height * CGFloat(position.centreY)
    }

    /// One cue as the renderer draws it: timeline seconds, and each word's
    /// timeline seconds for Word by Word.
    struct Cue: Equatable, Sendable {
        let id: UUID
        let start: Double
        let end: Double
        let text: String
        let words: [CaptionWord]
    }

    /// The lane's cues in timeline seconds, ready for the compositor: what
    /// is hidden by a trim is not here, word times follow the clip's speed.
    static func cues(_ lane: VideoCaptionLane?, in recipe: VideoProjectRecipe) -> [Cue] {
        let placements = CaptionTimeline.placements(recipe)
        return CaptionTimeline.placed(lane, in: recipe).map { placed in
            let clip = recipe.clips[placed.clipIndex]
            let placement = placements[placed.clipIndex]
            let sourceWords = placed.cue.words ?? CaptionEditing.evenWords(placed.cue)
            let words = sourceWords.compactMap { word -> CaptionWord? in
                guard let span = CaptionTimeline.timelineSpan(sourceStart: word.start, sourceEnd: max(word.end, word.start + 0.01), clip: clip, placement: placement)
                else { return nil }
                return CaptionWord(text: word.text, start: span.start, end: span.end)
            }
            return Cue(id: placed.cue.id, start: placed.start, end: placed.end, text: placed.cue.text, words: words)
        }
    }

    /// The cue on screen at timeline second `time`.
    static func cue(at time: Double, in cues: [Cue]) -> Cue? {
        cues.last { time >= $0.start && time < $0.end }
    }

    /// How many words Word by Word shows at `time`: each appears when it is
    /// said; none of a cue is hidden once its last word has begun.
    static func visibleWordCount(_ cue: Cue, at time: Double) -> Int {
        guard !cue.words.isEmpty else { return Int.max }
        return max(1, cue.words.filter { $0.start <= time + 0.000_1 }.count)
    }
}
