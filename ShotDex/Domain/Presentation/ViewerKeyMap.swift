import Foundation

/// The viewer's keys, one rule on every device (FS-02.01b §2, FS-18 01b §3,
/// decided 2026-10-04): "." is Favorite, as in Photos for the Mac; ← → step
/// one frame through a paused video and turn the page everywhere else.
enum ViewerKeyMap {
    enum Key: Sendable { case left, right, period }

    enum Action: Equatable, Sendable {
        case page(Int)
        case stepFrame(Int)
        case toggleFavorite
    }

    static func action(for key: Key, isVideo: Bool, isPlaying: Bool) -> Action {
        switch key {
        case .period: return .toggleFavorite
        case .left, .right:
            let delta = key == .left ? -1 : 1
            return isVideo && !isPlaying ? .stepFrame(delta) : .page(delta)
        }
    }
}
