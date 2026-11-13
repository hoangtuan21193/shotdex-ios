import Foundation

/// Which pager pages the viewer prepares around the one on screen
/// (FS-02 §8 D6): two each side, clipped to the list, nearest first so the
/// page a swipe reaches next is asked for first.
enum ViewerPreheat {
    static let radius = 2

    static func indices(around index: Int, count: Int, radius: Int = Self.radius) -> [Int] {
        guard count > 0, index >= 0, index < count else { return [] }
        var result = [index]
        for step in 1...max(radius, 1) {
            if index + step < count { result.append(index + step) }
            if index - step >= 0 { result.append(index - step) }
        }
        return result
    }
}
