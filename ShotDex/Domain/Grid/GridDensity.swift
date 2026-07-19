import Foundation

/// Date grouping used by the photo grid's section headers.
enum PhotoGridDateGranularity: Equatable, Sendable {
    case day
    case month
}

/// Pure math for the Photos/Metapho-style pinch-to-change-density gesture.
/// The grid steps through *contiguous* column counts one at a time: each
/// pinch-in adds a column, each pinch-out removes one (no continuous scale).
enum GridDensity {
    /// Column counts the grid can step through, densest to sparsest.
    static let columnRange = 1...8

    /// Sanitizes a persisted column count (legacy 1/3/5/9 or garbage) into
    /// the supported range.
    static func clamped(_ columns: Int) -> Int {
        min(max(columns, columnRange.lowerBound), columnRange.upperBound)
    }

    /// One step denser (`+1`) or sparser (`-1`), clamped to the range.
    static func stepped(_ current: Int, by delta: Int) -> Int {
        clamped(current + delta)
    }

    /// Wide cells get day headers; dense levels group by month.
    static func granularity(forColumns columns: Int) -> PhotoGridDateGranularity {
        columns <= 3 ? .day : .month
    }
}
