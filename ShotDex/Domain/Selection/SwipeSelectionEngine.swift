import CoreGraphics

/// Events emitted while a selection drag runs. `changed` carries the asset ids
/// of the full grid-order range from the drag's start tile to the tile
/// currently under the finger, recomputed each move — the screen applies it on
/// top of a baseline snapshot captured at `began`, so backtracking un-does.
enum SwipeSelectEvent {
    case began
    case changed(rangeIds: [String], select: Bool)
    case ended
}

/// Pure logic for iOS-Photos-style swipe selection. No SwiftUI.
///
/// A selection drag toggles the contiguous grid-order range between the tile
/// where the drag started and the tile currently under the finger. The range is
/// index-based, so cells recycled offscreen are still covered.
enum SwipeSelectionEngine {

    /// Direction lock decided from the first few points of a drag:
    /// mostly-horizontal drags select, mostly-vertical drags scroll.
    enum Activation {
        case undecided
        case select
        case scroll
    }

    /// Decides select-vs-scroll once the translation exceeds `threshold`.
    /// Horizontal movement must win clearly; diagonal/vertical movement stays
    /// with scrolling so entering selection mode does not make ordinary
    /// one-finger navigation accidentally toggle photos.
    static func activation(
        translation: CGSize,
        threshold: CGFloat = 8,
        horizontalDominance: CGFloat = 1.15
    ) -> Activation {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard max(dx, dy) >= threshold else { return .undecided }
        return dx > dy * horizontalDominance ? .select : .scroll
    }

    /// Per-display-frame auto-scroll step while an active selection drag sits
    /// inside the top/bottom edge band. Quadratic acceleration keeps the inner
    /// edge controllable and the physical edge fast enough for large ranges.
    static func autoScrollDelta(
        locationY: CGFloat,
        visibleBounds: CGRect,
        edgeInset: CGFloat = 72,
        maximumStep: CGFloat = 14
    ) -> CGFloat {
        guard edgeInset > 0, maximumStep > 0, !visibleBounds.isEmpty else { return 0 }
        let topDistance = locationY - visibleBounds.minY
        if topDistance < edgeInset {
            let progress = min(max(1 - topDistance / edgeInset, 0), 1)
            return -maximumStep * progress * progress
        }
        let bottomDistance = visibleBounds.maxY - locationY
        if bottomDistance < edgeInset {
            let progress = min(max(1 - bottomDistance / edgeInset, 0), 1)
            return maximumStep * progress * progress
        }
        return 0
    }
}
