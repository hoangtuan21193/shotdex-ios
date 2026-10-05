import CoreGraphics
import Foundation

/// Before and After (FS-12.15): the original frame beside — or under a
/// draggable line against — the graded one, playing and scrubbing on one
/// clock. Screen state only: it never enters the recipe, the undo stack or
/// an export (§5, §7).
struct VideoBeforeAfter: Equatable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Two frames side by side — the iPad and the Duo's inner display.
        case sideBySide
        /// One frame, Before left of a line the user drags — every device.
        case split
        /// One frame; holding a finger on it shows Before — the phone.
        case hold

        var id: String { rawValue }
    }

    var mode: Mode
    /// Where the Split line is, 0…1 across the frame; Before is left of it.
    var fraction: Double = 0.5
    /// iPad portrait's Swap sides: After on the left, Before on the right.
    var isSwapped = false

    /// The modes a window offers (§4): the phone and the Duo's cover Split ·
    /// Hold to Compare; the iPad and the Duo's inner display Side by Side ·
    /// Split.
    static func modes(sideBySide: Bool) -> [Mode] {
        sideBySide ? [.sideBySide, .split] : [.split, .hold]
    }

    /// The mode it opens in: Side by Side where there is room, else Split.
    static func opening(sideBySide: Bool) -> VideoBeforeAfter {
        VideoBeforeAfter(mode: sideBySide ? .sideBySide : .split)
    }

    /// Whether the frame is drawn as a pair — both sides in every frame.
    var drawsPair: Bool { mode != .hold }

    // MARK: What Before is (§3)

    /// The project as Before shows it: no look (the video's or any clip's),
    /// no grade — de-log included (§3: "Original clip"), no overlays, no
    /// captions. Cuts, speed, order, transitions, motion, rotation, ratio,
    /// background and sound stay.
    static func beforeRecipe(_ recipe: VideoProjectRecipe) -> VideoProjectRecipe {
        var before = recipe
        before.look = nil
        for index in before.clips.indices { before.clips[index].look = nil }
        before.nodes = [ColorNode()]
        before.inputTransform = .none
        before.overlays = []
        before.captions = nil
        return before
    }

    /// Nothing to compare (AC-10): Before and After would be the same
    /// picture — the button still works and says so.
    static func hasNothingToCompare(_ recipe: VideoProjectRecipe) -> Bool {
        recipe.look == nil
            && recipe.clips.allSatisfy { $0.look == nil }
            && !recipe.hasGrade
            && recipe.inputTransform.isIdentity
            && recipe.overlays.isEmpty
            && (recipe.captions?.cues.isEmpty ?? true)
    }

    // MARK: Geometry

    /// Two frames of `aspect` side by side in `box`, `inset` from its edges
    /// and `gap` apart, as large as they fit — iPad 448×252 (landscape) and
    /// 458×258 (portrait), the Duo's inner display 330×186 (§4).
    static func sideBySideFrames(in box: CGRect, aspect: CGFloat, inset: CGFloat, gap: CGFloat) -> (left: CGRect, right: CGRect) {
        let available = CGSize(width: max(0, box.width - 2 * inset - gap) / 2, height: max(0, box.height - 2 * inset))
        var size = CGSize(width: available.width, height: available.width / max(aspect, 0.01))
        if size.height > available.height {
            size = CGSize(width: available.height * aspect, height: available.height)
        }
        let total = size.width * 2 + gap
        let x = box.minX + (box.width - total) / 2
        let y = box.minY + (box.height - size.height) / 2
        return (
            CGRect(x: x, y: y, width: size.width, height: size.height),
            CGRect(x: x + size.width + gap, y: y, width: size.width, height: size.height)
        )
    }

    /// The Split line's x in `frame`.
    func lineX(in frame: CGRect) -> CGFloat {
        frame.minX + frame.width * CGFloat(min(max(fraction, 0), 1))
    }

    /// The fraction a drag to `x` sets, clamped to the frame (AC-3).
    static func fraction(forX x: CGFloat, in frame: CGRect) -> Double {
        guard frame.width > 0 else { return 0.5 }
        return Double(min(max((x - frame.minX) / frame.width, 0), 1))
    }

    /// VoiceOver steps the handle by a tenth.
    static let accessibilityStep = 0.1

    func adjusted(by steps: Int) -> VideoBeforeAfter {
        var copy = self
        copy.fraction = min(max((fraction + Double(steps) * Self.accessibilityStep), 0), 1)
        copy.fraction = (copy.fraction * 100).rounded() / 100
        return copy
    }

    /// "25" for "Before, 25 percent".
    var percent: Int { Int((fraction * 100).rounded()) }
}
