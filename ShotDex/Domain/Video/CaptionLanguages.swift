import Foundation

/// The languages Auto Captions offers (FS-12.14 §4): every language the
/// system recognises, the ones whose model is not on this device dimmed —
/// the app never downloads a model and never falls back to a server.
enum CaptionLanguages {
    struct Option: Identifiable, Equatable, Sendable {
        /// BCP-47, as the recogniser names it: "en-US".
        let id: String
        /// "English (US)", "Tiếng Việt" — each language in its own words.
        let name: String
        let isAvailable: Bool
    }

    /// One row per supported language, sorted by name; the region shows
    /// only where a language comes in more than one.
    static func options(supported: [String], isAvailable: (String) -> Bool) -> [Option] {
        let ids = Array(Set(supported.map(normalized))).sorted()
        let byLanguage = Dictionary(grouping: ids, by: languageCode)
        return ids.map { id in
            Option(id: id, name: name(of: id, showsRegion: (byLanguage[languageCode(id)]?.count ?? 0) > 1), isAvailable: isAvailable(id))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The device's language when its model is here, else English (US) —
    /// and nil when not even that can be recognised on this device.
    static func defaultLanguage(preferred: [String], isAvailable: (String) -> Bool) -> String? {
        for language in preferred.map(normalized) {
            if isAvailable(language) { return language }
            // "vi" on its own: the region the recogniser knows it by.
            if !language.contains("-"), let match = knownRegions[language], isAvailable(match) { return match }
        }
        return isAvailable(VideoCaptionLane.defaultLanguage) ? VideoCaptionLane.defaultLanguage : nil
    }

    /// Whether any language at all can be recognised here (§8: the row dims
    /// and says so when none can).
    static func hasAnyModel(supported: [String], isAvailable: (String) -> Bool) -> Bool {
        supported.contains { isAvailable(normalized($0)) }
    }

    /// "English (US)" / "Tiếng Việt".
    static func name(of id: String, showsRegion: Bool = true) -> String {
        let locale = Locale(identifier: id)
        let code = languageCode(id)
        let language = (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
        guard showsRegion, let region = id.split(separator: "-").dropFirst().last, region.count == 2 else { return language }
        return "\(language) (\(region))"
    }

    static func normalized(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: "-")
    }

    static func languageCode(_ id: String) -> String {
        String(normalized(id).split(separator: "-").first ?? "")
    }

    private static let knownRegions = ["en": "en-US", "vi": "vi-VN", "ja": "ja-JP", "de": "de-DE", "fr": "fr-FR", "es": "es-ES"]
}
