import CoreGraphics

/// How a timed overlay enters and leaves its visibility window.
///
/// The same set is offered for the in ramp and the out ramp, chosen
/// independently, the way CapCut / InShot separate "in" and "out" animations.
enum OverlayAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case fade
    case slideUp
    case slideDown
    case slideLeft
    case slideRight
    case pop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: String(localized: "None")
        case .fade: String(localized: "Fade")
        case .slideUp: String(localized: "Slide up")
        case .slideDown: String(localized: "Slide down")
        case .slideLeft: String(localized: "Slide left")
        case .slideRight: String(localized: "Slide right")
        case .pop: String(localized: "Pop")
        }
    }

    var systemImage: String {
        switch self {
        case .none: "slash.circle"
        case .fade: "circle.righthalf.filled"
        case .slideUp: "arrow.up"
        case .slideDown: "arrow.down"
        case .slideLeft: "arrow.left"
        case .slideRight: "arrow.right"
        case .pop: "sparkles"
        }
    }
}

/// Pure geometry for the overlay in/out animations — no CoreImage, no UIKit, so it
/// is unit-tested and shared by the export compositor and the preview proxy.
enum OverlayAnimationMath {
    /// A layer's animated deviation from its resting pose.
    ///
    /// `translation` is in screen-space fractions of the render extent (x to the
    /// right, y downward); `scale` and `opacity` multiply the resting values.
    /// Identity means fully settled — the layer sits exactly where it was placed.
    struct Transform: Equatable {
        var opacity: Double
        var translation: CGSize
        var scale: Double

        static let identity = Transform(opacity: 1, translation: .zero, scale: 1)

        /// Stack two ramps (an in and an out never actually overlap in a well-formed
        /// window, but the combine is defined for completeness): opacities and
        /// scales multiply, translations add.
        func combined(with other: Transform) -> Transform {
            Transform(
                opacity: opacity * other.opacity,
                translation: CGSize(
                    width: translation.width + other.translation.width,
                    height: translation.height + other.translation.height
                ),
                scale: scale * other.scale
            )
        }
    }

    /// Travel distance for the slide animations, as a fraction of the render
    /// extent's matching edge.
    static let slideOffset: Double = 0.12
    /// Starting scale for the pop animation.
    static let popScale: Double = 0.4

    /// The pose while entering: `progress` 0 (just appeared) → 1 (settled), eased.
    static func enter(_ kind: OverlayAnimation, progress: Double) -> Transform {
        let p = easeOut(clamp01(progress))
        let remaining = 1 - p
        switch kind {
        case .none:
            return .identity
        case .fade:
            return Transform(opacity: p, translation: .zero, scale: 1)
        case .slideUp:
            return Transform(opacity: p, translation: CGSize(width: 0, height: remaining * slideOffset), scale: 1)
        case .slideDown:
            return Transform(opacity: p, translation: CGSize(width: 0, height: -remaining * slideOffset), scale: 1)
        case .slideLeft:
            return Transform(opacity: p, translation: CGSize(width: remaining * slideOffset, height: 0), scale: 1)
        case .slideRight:
            return Transform(opacity: p, translation: CGSize(width: -remaining * slideOffset, height: 0), scale: 1)
        case .pop:
            return Transform(opacity: p, translation: .zero, scale: popScale + (1 - popScale) * p)
        }
    }

    /// The pose while leaving: `progress` 0 (settled) → 1 (gone), eased. The layer
    /// exits in the named direction.
    static func exit(_ kind: OverlayAnimation, progress: Double) -> Transform {
        let p = easeIn(clamp01(progress))
        switch kind {
        case .none:
            return .identity
        case .fade:
            return Transform(opacity: 1 - p, translation: .zero, scale: 1)
        case .slideUp:
            return Transform(opacity: 1 - p, translation: CGSize(width: 0, height: -p * slideOffset), scale: 1)
        case .slideDown:
            return Transform(opacity: 1 - p, translation: CGSize(width: 0, height: p * slideOffset), scale: 1)
        case .slideLeft:
            return Transform(opacity: 1 - p, translation: CGSize(width: -p * slideOffset, height: 0), scale: 1)
        case .slideRight:
            return Transform(opacity: 1 - p, translation: CGSize(width: p * slideOffset, height: 0), scale: 1)
        case .pop:
            return Transform(opacity: 1 - p, translation: .zero, scale: 1 - (1 - popScale) * p)
        }
    }

    static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Decelerating ease for entrances — fast off the mark, gentle into place.
    static func easeOut(_ t: Double) -> Double {
        let x = clamp01(t)
        return 1 - (1 - x) * (1 - x)
    }

    /// Accelerating ease for exits — gentle to leave, quick to clear.
    static func easeIn(_ t: Double) -> Double {
        let x = clamp01(t)
        return x * x
    }
}
