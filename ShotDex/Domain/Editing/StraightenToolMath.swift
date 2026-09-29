import CoreGraphics

/// The Straighten Tool's ruler (FS-03.13b §3): a line dragged along
/// something that should be level turns into the angle that levels it.
///
/// Screen points, y down. Core Image rotates a positive `straightenDegrees`
/// counter-clockwise on screen, so a line whose right end is lower (drawn
/// clockwise of level) needs a positive correction.
enum StraightenToolMath {
    /// Shorter than this on screen is a tap, not a ruler.
    static let minimumLength: CGFloat = 8

    /// Degrees to add to the photo's angle so the line from `start` to `end`
    /// lies level — or, when it is more than 45° off level (a pillar, a
    /// tree), stands upright, as Lightroom and Guided do. `nil` for a line
    /// shorter than `minimumLength` on screen; `zoom` turns the stage's
    /// points into the screen's.
    static func correction(from start: CGPoint, to end: CGPoint, zoom: CGFloat = 1) -> Double? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) * zoom >= minimumLength else { return nil }
        // The direction of the stroke does not matter: fold into -90…90.
        var degrees = Double(atan2(dy, dx)) * 180 / .pi
        if degrees > 90 { degrees -= 180 } else if degrees < -90 { degrees += 180 }
        if abs(degrees) <= 45 { return degrees }
        return degrees > 0 ? degrees - 90 : degrees + 90
    }

    /// The photo's angle after the correction, inside Straighten's ±45°.
    static func angle(current: Double, adding correction: Double) -> Double {
        min(45, max(-45, current + correction))
    }
}
