import CoreGraphics
import Photos

/// What the culling pass asks PhotoKit for (FS-01.12b §2, AC-8): a
/// screen-sized rendition with the network allowed, the current page and two
/// on each side kept warm — **never** the original. A shoot is judged at
/// screen size; pulling 800 originals over cellular to do it is the failure
/// this exists to prevent. Pure.
enum CullImagePolicy {
    static let allowsNetwork = true
    static let warmRadius = 2

    /// The screen in pixels, capped — never `PHImageManagerMaximumSize`.
    static func targetSize(screen: CGSize, scale: CGFloat) -> CGSize {
        let longest: CGFloat = 2_800
        let width = max(1, screen.width * scale)
        let height = max(1, screen.height * scale)
        let fit = min(1, longest / max(width, height))
        return CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
    }

    static func warmRange(index: Int, count: Int) -> ClosedRange<Int>? {
        guard count > 0, (0..<count).contains(index) else { return nil }
        return max(0, index - warmRadius)...min(count - 1, index + warmRadius)
    }
}
