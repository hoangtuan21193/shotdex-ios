import CoreGraphics
import Foundation

/// Decides which touches on the photo are strokes and which belong to zoom and
/// pan. Pure logic, no UIKit: `EditorPaintTouchLayer` feeds it touch events and
/// applies whatever it returns.
///
/// The rules come from what went wrong when the paint layer decided this itself,
/// with nothing but "is this the only touch in the event I was just handed":
///
/// - Two fingers never land at the same instant. Twenty to sixty milliseconds
///   apart is normal, so every pinch opened a stroke, painted a dab, and rolled
///   it back — visible as a flicker, and a wasted Clean Up solve.
/// - Fingers do not lift together either. The last one left over from a pan
///   slides a few points before it goes, and that painted.
/// - A finger that re-touches mid-pan looked, to the layer, exactly like the
///   first finger of a fresh stroke: the event carried one touch, and the
///   cancelled recogniser had already forgotten the other finger. Brushing while
///   panning with two fingers was the bug that made the tool unusable.
///
/// So a touch has to earn the right to paint. It is buffered while the verdict is
/// out, and the buffer is handed over intact once it wins — nothing the finger
/// did is lost by waiting.
struct PaintTouchArbiter {
    struct Parameters {
        /// How long a lone finger must survive before its stroke is real. Sized
        /// to outlast the gap between the two fingers of a pinch.
        var confirmationDelay: TimeInterval = 0.08
        /// Or how far it must travel — a finger that has moved this far is
        /// painting, whatever it might have become.
        var confirmationDistance: CGFloat = 4
        /// A confirmed stroke that has covered this much is kept when a second
        /// finger arrives: it ends where it is instead of being thrown away. The
        /// alternative loses a carefully painted stroke to a graze of the palm.
        var keptStrokeDistance: CGFloat = EditorLayoutMetrics.gestureArbitrationDistance
        /// Quiet period after the last finger of a multi-touch gesture lifts.
        /// Without it, the straggler finger of a pan paints on its way up.
        var cooldown: TimeInterval = 0.25

        init() {}
    }

    /// What the layer should do about the touch it just reported.
    enum Decision: Equatable {
        /// Not a stroke, and never will be. The cursor comes off the photo.
        case ignore
        /// Might become a stroke: follow the finger with the cursor, change nothing.
        case track(CGPoint)
        /// Confirmed. Every point the finger has visited so far, oldest first.
        case begin([CGPoint])
        case extend(CGPoint)
        /// Ends the stroke and keeps it.
        case finish
        /// Ends the stroke and rolls it back, history entry included.
        case discard
    }

    private enum Phase: Equatable {
        case idle
        /// Buffering: the finger is down and alone, but has not earned a stroke yet.
        case pending(start: TimeInterval, from: CGPoint, points: [CGPoint])
        /// Painting, carrying how far the finger has travelled since touch-down.
        case painting(from: CGPoint, travelled: CGFloat)
        /// A stroke that ended abnormally, or a touch refused outright. Stays here
        /// until every finger is off the photo.
        case refused
    }

    private var parameters: Parameters
    private var phase = Phase.idle
    /// Set the moment a second finger is seen anywhere in the sequence, cleared
    /// only when the photo is untouched again. This is what stops a re-touch
    /// mid-pan from reading as a new stroke.
    private var isMultiTouchSequence = false
    private var multiTouchEndedAt: TimeInterval?

    init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    /// A finger touched down. `activeTouches` counts every finger on the paint
    /// layer including this one.
    mutating func touchDown(
        activeTouches: Int,
        at point: CGPoint,
        time: TimeInterval
    ) -> Decision {
        if activeTouches > 1 {
            isMultiTouchSequence = true
        }
        guard activeTouches == 1, !isMultiTouchSequence, !isCoolingDown(at: time) else {
            phase = .refused
            return .ignore
        }
        phase = .pending(start: time, from: point, points: [point])
        return .track(point)
    }

    mutating func touchMoved(to point: CGPoint, time: TimeInterval) -> Decision {
        switch phase {
        case .pending(let start, let from, var points):
            points.append(point)
            let travelled = distance(from, point)
            guard time - start >= parameters.confirmationDelay
                    || travelled >= parameters.confirmationDistance
            else {
                phase = .pending(start: start, from: from, points: points)
                return .track(point)
            }
            phase = .painting(from: from, travelled: travelled)
            return .begin(points)
        case .painting(let from, let travelled):
            phase = .painting(from: from, travelled: max(travelled, distance(from, point)))
            return .extend(point)
        case .idle, .refused:
            return .ignore
        }
    }

    /// The painting finger lifted. A finger that is gone cannot turn into a
    /// pinch, so even a touch still inside the confirmation window paints here —
    /// which is what makes a tap lay down exactly one dab.
    mutating func touchUp(time: TimeInterval) -> Decision {
        switch phase {
        case .pending(_, _, let points):
            phase = .idle
            return .begin(points)
        case .painting:
            phase = .idle
            return .finish
        case .idle, .refused:
            phase = .idle
            return .ignore
        }
    }

    /// A second finger arrived while a stroke was in progress: the touch is a
    /// pinch or a pan, not a stroke.
    mutating func extraFingerDown(time: TimeInterval) -> Decision {
        isMultiTouchSequence = true
        let decision = endedByAnotherGesture()
        phase = .refused
        return decision
    }

    /// The system took the touches away — an incoming call, a system gesture.
    /// Judged the same way: keep a stroke that had become one, drop a stub.
    mutating func systemCancelled() -> Decision {
        let decision = endedByAnotherGesture()
        phase = .refused
        return decision
    }

    /// Every finger is off the photo. Clears the latch and starts the cooldown if
    /// the sequence had ever been multi-touch.
    mutating func allFingersUp(time: TimeInterval) {
        if isMultiTouchSequence {
            multiTouchEndedAt = time
        }
        isMultiTouchSequence = false
        phase = .idle
    }

    private mutating func endedByAnotherGesture() -> Decision {
        switch phase {
        case .painting(_, let travelled) where travelled >= parameters.keptStrokeDistance:
            return .finish
        case .painting:
            return .discard
        case .pending:
            // The whole point of the buffer: nothing was ever written, so there
            // is nothing to roll back and nothing to undo. The pinch leaves no
            // trace at all.
            return .ignore
        case .idle, .refused:
            return .ignore
        }
    }

    private func isCoolingDown(at time: TimeInterval) -> Bool {
        guard let multiTouchEndedAt else { return false }
        return time - multiTouchEndedAt < parameters.cooldown
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
