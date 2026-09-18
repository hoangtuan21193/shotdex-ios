import CoreGraphics
import Foundation

/// Date grouping used by the photo grid's section headers.
enum PhotoGridDateGranularity: Equatable, Sendable {
    case day
    case month
    case year
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

    /// The zoom ladder Photos walks with a pinch: wide cells get day headers,
    /// middle densities group by month, and the densest levels group by year.
    /// Density is the only control — there is no separate Years/Months/Days
    /// switch, because pinching already expresses the same intent.
    static func granularity(forColumns columns: Int) -> PhotoGridDateGranularity {
        switch columns {
        case ...3: .day
        case 4...6: .month
        default: .year
        }
    }

    /// Content width the persisted column count is expressed at — a compact
    /// iPhone in portrait.
    static let compactReferenceWidth: CGFloat = 393

    /// How many columns to actually draw for a persisted density at the width
    /// the grid really has.
    ///
    /// iPhone Duo's inner display is 626pt wide and horizontally *regular*:
    /// drawing the stored 3 columns there would double the size of every tile
    /// instead of showing more photos. On a regular-width display the count
    /// scales with the width, so the tile size the user pinched to survives
    /// unfolding. Compact width — every current iPhone, and the Duo's outer
    /// display — is returned untouched, so nothing shipping today changes.
    static func columns(forDensity density: Int, width: CGFloat, isRegularWidth: Bool) -> Int {
        let density = clamped(density)
        guard isRegularWidth, width > compactReferenceWidth else { return density }
        let scaled = (CGFloat(density) * width / compactReferenceWidth).rounded()
        return clamped(Int(scaled))
    }
}
