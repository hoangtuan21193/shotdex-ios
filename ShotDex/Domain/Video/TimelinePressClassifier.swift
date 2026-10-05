import CoreGraphics
import Foundation

/// The three gestures a finger can make on a clip's body (FS-12.11 §4),
/// told apart by how long it held and how far it travelled:
///
/// | Held | Then | Outcome |
/// |---|---|---|
/// | under 0.32 s | moves more than 10pt | scrolls the timeline |
/// | 0.32 s or more | moves more than 10pt | moves the clip — the whole group if it is in one |
/// | 0.5 s or more, 10pt or less | lets go | enters multi-select with that clip |
/// | 0.32–0.5 s, 10pt or less | lets go | nothing — no selection, no move, no undo step |
/// | under 0.32 s, 10pt or less | lets go | an ordinary tap |
///
/// The numbers live here and nowhere else: the timeline's UIKit long-press
/// waits `movePress` and allows `slop`, then asks this type what the press
/// was when the finger lifts.
enum TimelinePressClassifier {
    enum Outcome: Equatable, Sendable {
        /// Travel before the press fired: the scroll view's pan has it.
        case scroll
        /// Held, then dragged: the clip (or its group) is moving.
        case move
        /// Held long and let go in place: multi-select begins.
        case enterSelection
        /// Held too long for a tap, too short to select: nothing happens.
        case nothing
        /// A quick touch and release.
        case tap
        /// Still down, still in place: not decided yet.
        case pending
    }

    /// How long a press must hold before a drag moves the clip — and the
    /// UIKit long-press's `minimumPressDuration`.
    static let movePress: TimeInterval = 0.32
    /// How long a press must hold, let go in place, to enter multi-select.
    static let selectPress: TimeInterval = 0.5
    /// Travel, in points, that still counts as "in place".
    static let slop: CGFloat = 10

    /// What a press on a clip's body is, `held` seconds after the finger
    /// came down and `travel` points from where it did. `isReleased` is
    /// whether the finger has lifted.
    static func classify(held: TimeInterval, travel: CGFloat, isReleased: Bool) -> Outcome {
        if travel > slop {
            return held < movePress ? .scroll : .move
        }
        guard isReleased else { return .pending }
        if held >= selectPress { return .enterSelection }
        if held >= movePress { return .nothing }
        return .tap
    }
}
