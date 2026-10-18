import Foundation

/// How a numeric rule field parses and formats its value (ISO, aperture,
/// shutter) — shared by the rule model and its editor.
enum NumericFieldKind {
    case int      // ISO
    case double   // aperture, focal length
    case shutter  // seconds; accepts "1/500" or decimal
}

extension NumericFieldKind {
    /// Parses user text into a stored `Double?` (nil = empty / unparseable).
    /// `.shutter` also accepts a "1/500" fraction.
    func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch self {
        case .int, .double:
            return Double(trimmed)
        case .shutter:
            if trimmed.contains("/") {
                let parts = trimmed.split(separator: "/")
                guard parts.count == 2,
                      let numerator = Double(parts[0]),
                      let denominator = Double(parts[1]), denominator != 0
                else { return nil }
                return numerator / denominator
            }
            return Double(trimmed)
        }
    }

    /// Formats a stored value for display (empty string when nil).
    func format(_ value: Double?) -> String {
        guard let value else { return "" }
        switch self {
        case .int:
            return String(Int(value.rounded()))
        case .double:
            return Self.trimmed(value)
        case .shutter:
            if value > 0, value < 1 {
                return "1/\(Int((1 / value).rounded()))"
            }
            return Self.trimmed(value)
        }
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
