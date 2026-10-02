import CoreGraphics

/// What a swipe on the photo means in the pass (FS-01.12b §2, §5). Pure.
///
/// At fit (1×) a vertical swipe flags — up Pick, down Reject — and a
/// horizontal one turns the page. Zoomed in, every drag moves the photo
/// and nothing is flagged: a pass must never mark a photo while someone is
/// inspecting it.
enum CullGesturePolicy {
    enum Swipe: Equatable, Sendable { case up, down, left, right }

    enum Action: Equatable, Sendable {
        case flag(PhotoFlag)
        case previous
        case next
    }

    /// Above this the photo is zoomed — the same 1% slack the viewer uses.
    static let fitTolerance: CGFloat = 1.01

    static func action(for swipe: Swipe, zoomScale: CGFloat) -> Action? {
        guard zoomScale <= fitTolerance else { return nil }
        switch swipe {
        case .up: return .flag(.pick)
        case .down: return .flag(.reject)
        case .left: return .next
        case .right: return .previous
        }
    }
}
