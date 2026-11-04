import Foundation

/// A typed bound of a range filter — the Mac popover's Focal, ISO and
/// Aperture fields (FS-18.02 §5). Apart from SwiftUI so a typo's handling is
/// tested: an empty field clears the bound, anything unreadable keeps it.
enum RangeBoundInput: Sendable {
    case focal, iso, aperture

    enum Result: Equatable {
        /// The field was emptied: no bound.
        case cleared
        /// Not a usable number: keep the bound the filter holds.
        case invalid
        case value(Double)
    }

    /// The usual stops the field's menu offers.
    var stops: [Double] {
        switch self {
        case .focal: [14, 24, 35, 50, 85, 135, 200, 400]
        case .iso: [100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600]
        case .aperture: [1.2, 1.4, 1.8, 2, 2.8, 4, 5.6, 8, 11, 16]
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .focal: NumericFieldKind.double.format(value)
        case .iso: NumericFieldKind.int.format(value)
        case .aperture: "f/" + NumericFieldKind.double.format(value)
        }
    }

    /// "f/2.8", "85mm", "3200": a finite number above zero; ISO rounds to a
    /// whole number.
    func parse(_ text: String) -> Result {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return .cleared }
        if self == .aperture, trimmed.hasPrefix("f/") { trimmed.removeFirst(2) }
        if self == .aperture, trimmed.hasPrefix("f") { trimmed.removeFirst() }
        if self == .focal, trimmed.hasSuffix("mm") { trimmed.removeLast(2) }
        if self == .iso, trimmed.hasPrefix("iso") { trimmed.removeFirst(3) }
        guard let number = NumericFieldKind.double.parse(trimmed), number.isFinite, number > 0 else { return .invalid }
        return .value(self == .iso ? number.rounded() : number)
    }

    /// `range` with `bound` set — and the two swapped when they cross, so
    /// "3200 to 400" means 400–3200 instead of nothing.
    static func setting(_ bound: Double?, lower: Bool, in range: NumericRangeFilter) -> NumericRangeFilter {
        var range = range
        if lower { range.lowerBound = bound } else { range.upperBound = bound }
        if let low = range.lowerBound, let high = range.upperBound, low > high {
            range = NumericRangeFilter(lowerBound: high, upperBound: low)
        }
        return range
    }
}
