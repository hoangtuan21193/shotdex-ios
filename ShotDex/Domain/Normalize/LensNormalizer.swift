import Foundation

/// Normalizes lens model strings so the same physical lens written in
/// different EXIF spellings groups as one:
/// `RF100-500mm F4.5-7.1 L IS USM`, `Canon RF100-500mm F4.5-7.1 L IS USM`
/// and `RF 100-500mm F4.5-7.1L IS USM` all normalize identically.
/// Pure Swift, no framework dependencies.
enum LensNormalizer {

    private static let makerPrefixes = [
        "canon", "nikon", "nikkor", "sony", "fujifilm", "fujinon", "olympus",
        "om system", "panasonic", "lumix", "leica", "sigma", "tamron",
        "samyang", "rokinon", "viltrox", "laowa", "zeiss", "voigtlander",
    ]

    /// Canonical display form of a lens model.
    static func normalize(_ raw: String?) -> String? {
        guard var value = clean(raw) else { return nil }

        // Strip a leading maker name ("Canon RF..." → "RF...").
        let lowered = value.lowercased()
        for maker in makerPrefixes where lowered.hasPrefix(maker + " ") {
            value = String(value.dropFirst(maker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        // Insert a space between a leading mount code and the focal number:
        // "RF100-500mm" → "RF 100-500mm".
        value = value.replacing(/^([A-Za-z]{1,4}(?:-[A-Za-z]{1,2})?)(\d)/) { match in
            "\(match.1) \(match.2)"
        }

        // Insert a space between "mm" and a glued aperture: "23mmF1.4" → "23mm F1.4".
        value = value.replacing(/(mm)([Ff]\d)/) { match in
            "\(match.1) \(match.2)"
        }

        // Insert a space between an aperture number and a trailing letter
        // block: "F4.5-7.1L" → "F4.5-7.1 L".
        value = value.replacing(/(\d(?:\.\d)?)((?:L|II|III)\b)/) { match in
            "\(match.1) \(match.2)"
        }

        // Unify aperture notation "f/2.8" → "F2.8".
        value = value.replacing(/\bf\/(\d)/.ignoresCase()) { match in
            "F\(match.1)"
        }

        let collapsed = value
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Grouping key: case-, space- and hyphen-insensitive.
    static func groupingKey(_ normalized: String) -> String {
        normalized.lowercased().filter { !$0.isWhitespace }
    }

    /// True when the lens model describes a zoom (focal range like `100-500mm`).
    static func isZoom(_ model: String?) -> Bool {
        guard let model else { return false }
        return model.contains(/\d+(?:\.\d+)?\s*-\s*\d+(?:\.\d+)?\s*mm/.ignoresCase())
    }

    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
