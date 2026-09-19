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
    /// Column counts a pinch steps through. This is the *stored* density, and
    /// it is always expressed at compact width.
    static let columnRange = 1...8

    /// Column counts the grid may actually draw. A regular-width display
    /// resolves the stored density into more columns than a pinch can reach,
    /// so this ceiling sits well above `columnRange`'s: a landscape 13" iPad
    /// at density 3 wants fourteen.
    static let resolvedColumnRange = 1...20

    /// Sanitizes a persisted column count (legacy 1/3/5/9 or garbage) into
    /// the supported range.
    static func clamped(_ columns: Int) -> Int {
        min(max(columns, columnRange.lowerBound), columnRange.upperBound)
    }

    /// Sanitizes a *drawn* column count into the range the layout supports.
    static func clampedResolved(_ columns: Int) -> Int {
        min(max(columns, resolvedColumnRange.lowerBound), resolvedColumnRange.upperBound)
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

    /// How much tighter tiles run on a regular-width display, as a fraction of
    /// the compact tile. An iPad or an unfolded Duo has far more room and is
    /// held further away, so reproducing the iPhone tile size one-for-one
    /// leaves a handful of enormous thumbnails and a lot of white — which is
    /// exactly what Photos does *not* do. At 0.7 a density-3 grid draws 9
    /// columns on a portrait 11-inch iPad (13 in landscape) and 9 on the Duo's
    /// inner screen, against 8-at-most before.
    static let regularTileScale: CGFloat = 0.7

    /// How many columns to actually draw for a persisted density at the width
    /// the grid really has.
    ///
    /// Compact width — every current iPhone, and the Duo's outer display — is
    /// returned untouched, so nothing shipping today changes. A regular-width
    /// display scales the count with the width so the tile size the user
    /// pinched to survives unfolding, then tightens it by `regularTileScale`
    /// because a big screen earns more photos per row, not bigger ones.
    static func columns(forDensity density: Int, width: CGFloat, isRegularWidth: Bool) -> Int {
        let density = clamped(density)
        guard isRegularWidth, width > compactReferenceWidth else { return density }
        let reference = compactReferenceWidth * regularTileScale
        let scaled = (CGFloat(density) * width / reference).rounded()
        return clampedResolved(max(density, Int(scaled)))
    }
}
