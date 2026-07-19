import CoreGraphics

/// Pure logic for iOS-Photos-style swipe selection. No SwiftUI.
///
/// A swipe-select drag toggles the contiguous grid-order range between the
/// tile where the drag started and the tile currently under the finger.
/// The range is index-based so tiles recycled offscreen by LazyVGrid are
/// still covered; frames are only needed to hit-test the finger position.
enum SwipeSelectionEngine {

    /// Direction lock decided from the first few points of a drag:
    /// mostly-horizontal drags select, mostly-vertical drags scroll.
    enum Activation {
        case undecided
        case select
        case scroll
    }

    /// Decides select-vs-scroll once the translation exceeds `threshold`.
    /// Ties go to `select` so a perfect diagonal still picks photos.
    static func activation(translation: CGSize, threshold: CGFloat = 8) -> Activation {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard max(dx, dy) >= threshold else { return .undecided }
        return dx >= dy ? .select : .scroll
    }

    /// Ids in the grid-order range between `startId` and `currentId`,
    /// inclusive, in either drag direction. Empty if either id is unknown.
    static func rangeIds(orderedIds: [String], startId: String, currentId: String) -> [String] {
        guard let startIndex = orderedIds.firstIndex(of: startId),
              let currentIndex = orderedIds.firstIndex(of: currentId)
        else { return [] }
        let range = min(startIndex, currentIndex)...max(startIndex, currentIndex)
        return Array(orderedIds[range])
    }

    /// Id of the tile whose frame contains `point`, nil in gaps/headers.
    static func tileId(at point: CGPoint, frames: [String: CGRect]) -> String? {
        frames.first { $0.value.contains(point) }?.key
    }
}
