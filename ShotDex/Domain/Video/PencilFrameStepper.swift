import CoreGraphics
import Foundation

/// Apple Pencil on a trimmed edge (FS-12.17 §8): a Pencil that rests — no
/// more than 2pt of drift for 0.3 s — in the middle of a stroke switches
/// the rest of that stroke to frame steps, one frame per 12pt, whatever the
/// timeline's zoom. Before it rests the stroke moves the edge as a finger
/// would.
///
/// Pure: the timeline feeds it the Pencil's x and the time of each sample.
struct PencilFrameStepper: Equatable, Sendable {
    /// How far the Pencil may drift and still be resting.
    static let stillTolerance: CGFloat = 2
    /// How long it has to rest.
    static let stillDuration: TimeInterval = 0.3
    /// Frame steps after the rest: 12pt a frame.
    static let pointsPerFrame: CGFloat = 12

    /// What the Pencil does on the lanes (§8): moves the edge it touches,
    /// or — after a double-tap — moves the playhead and leaves edges be.
    enum Mode: Equatable, Sendable {
        case trim, scrub

        var toggled: Mode { self == .trim ? .scrub : .trim }
    }

    private var stillX: CGFloat
    private var stillSince: TimeInterval
    /// Where frame stepping began, once the Pencil has rested.
    private(set) var stepOrigin: CGFloat?

    init(x: CGFloat, time: TimeInterval) {
        stillX = x
        stillSince = time
    }

    var isStepping: Bool { stepOrigin != nil }

    /// One sample of the stroke.
    mutating func sample(x: CGFloat, time: TimeInterval) {
        guard stepOrigin == nil else { return }
        if abs(x - stillX) > Self.stillTolerance {
            stillX = x
            stillSince = time
            return
        }
        if time - stillSince >= Self.stillDuration {
            stepOrigin = x
        }
    }

    /// Frames the stepping part of the stroke has moved by `x`: one per
    /// 12pt, a part frame not yet counted. Nil before the rest.
    func steppedFrames(at x: CGFloat) -> Int? {
        stepOrigin.map { Int(((x - $0) / Self.pointsPerFrame).rounded(.towardZero)) }
    }

    /// The translation, in points of the timeline at `pps`, that puts the
    /// edge where the stroke means it: the free part as drawn, then the
    /// stepped frames at the timeline's own frame width.
    func effectiveTranslation(from start: CGFloat, to x: CGFloat, pps: CGFloat, fps: Int) -> CGFloat {
        guard let origin = stepOrigin, let frames = steppedFrames(at: x) else { return x - start }
        return (origin - start) + CGFloat(frames) * pps / CGFloat(max(1, fps))
    }
}
