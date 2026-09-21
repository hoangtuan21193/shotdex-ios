import Foundation

/// Which line a finger landed on.
///
/// Pure, because "tapping here selects the date" is the complaint that
/// started this and it should be a test, not a thing checked by tapping. The
/// rules: a touch inside a line picks it; a touch in the gap between lines
/// picks the nearest one within reach; and when lines overlap, the smallest
/// wins, because the small one is the harder target and the big one can be
/// grabbed anywhere else along its length.
enum PhotoWidgetHitTest {
    /// How far outside a line still counts, in points. Lines of text are thin
    /// and the preview is 158pt tall.
    static let reach: CGFloat = 10

    static func component(
        at point: CGPoint,
        frames: [PhotoWidgetComponent: CGRect],
        reach: CGFloat = reach
    ) -> PhotoWidgetComponent? {
        let hits = frames.filter { $0.value.insetBy(dx: -2, dy: -2).contains(point) }
        if !hits.isEmpty {
            return hits.min { area($0.value) < area($1.value) }?.key
        }
        // Nothing directly under the finger: take the closest line that is
        // still within reach, so a tap just under a one-line clock does not
        // land on nothing.
        let near = frames.compactMap { component, rect -> (PhotoWidgetComponent, CGFloat)? in
            let distance = self.distance(from: point, to: rect)
            return distance <= reach ? (component, distance) : nil
        }
        return near.min { $0.1 < $1.1 }?.0
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
