import Foundation

/// Normalizes camera manufacturer and model strings coming from EXIF.
/// Pure Swift, no framework dependencies.
enum CameraNormalizer {

    /// Canonical manufacturer names keyed by lowercase EXIF `Make` values.
    private static let manufacturerAliases: [String: String] = [
        "canon": "Canon",
        "nikon": "Nikon",
        "nikon corporation": "Nikon",
        "sony": "Sony",
        "sony corporation": "Sony",
        "fujifilm": "Fujifilm",
        "fuji photo film co., ltd.": "Fujifilm",
        "olympus": "Olympus",
        "olympus corporation": "Olympus",
        "olympus imaging corp.": "Olympus",
        "om digital solutions": "OM System",
        "panasonic": "Panasonic",
        "leica": "Leica",
        "leica camera ag": "Leica",
        "ricoh": "Ricoh",
        "ricoh imaging company, ltd.": "Ricoh",
        "pentax": "Pentax",
        "pentax corporation": "Pentax",
        "hasselblad": "Hasselblad",
        "apple": "Apple",
        "samsung": "Samsung",
        "google": "Google",
        "dji": "DJI",
        "gopro": "GoPro",
        "sigma": "Sigma",
    ]

    /// Trims, collapses whitespace, and maps known manufacturer aliases.
    static func normalizeManufacturer(_ raw: String?) -> String? {
        guard let cleaned = clean(raw) else { return nil }
        return manufacturerAliases[cleaned.lowercased()] ?? cleaned
    }

    /// Normalizes an EXIF `Model` string: trims, collapses whitespace, and
    /// removes a duplicated manufacturer prefix ("Canon EOS R6" → "EOS R6"
    /// when the manufacturer is already known to be Canon).
    static func normalizeModel(_ raw: String?, manufacturer: String?) -> String? {
        guard var model = clean(raw) else { return nil }
        if let manufacturer = normalizeManufacturer(manufacturer) {
            model = strippingPrefix(manufacturer, from: model)
            // Also strip raw aliases of the same manufacturer ("NIKON CORPORATION").
            for (alias, canonical) in manufacturerAliases where canonical == manufacturer {
                model = strippingPrefix(alias, from: model)
            }
        }
        return model.isEmpty ? nil : model
    }

    /// Key used for case/spacing-insensitive lookups in the sensor database.
    static func lookupKey(_ model: String) -> String {
        model.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    private static func strippingPrefix(_ prefix: String, from value: String) -> String {
        guard value.lowercased().hasPrefix(prefix.lowercased() + " ") else { return value }
        return String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
