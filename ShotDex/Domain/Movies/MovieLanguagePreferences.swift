import Foundation

/// Settings › Playback › Audio Languages and Subtitle Languages (FS-23.02
/// §3b, 03 §2): an ordered list of language codes, first match wins.
enum MovieLanguagePreferences {
    /// The languages offered, most common for films first; any code a file
    /// carries still matches through `MovieLanguage.code`.
    static let offered = [
        "en", "vi", "ja", "ko", "zh", "fr", "de", "es", "it", "pt", "ru", "th", "id", "ms", "fil",
        "hi", "ar", "tr", "pl", "nl", "sv", "no", "da", "fi", "cs", "hu", "el", "he", "uk", "ro",
    ]

    /// Audio: unwritten or empty = Original (the file's default track).
    static func audio(_ stored: String?) -> [String] {
        decode(stored) ?? []
    }

    /// Subtitles: unwritten = the device language then English; empty = none.
    static func subtitles(_ stored: String?, deviceLanguage: String?) -> [String] {
        if let list = decode(stored) { return list }
        var list: [String] = []
        if let device = MovieLanguage.code(deviceLanguage) { list.append(device) }
        if !list.contains("en") { list.append("en") }
        return list
    }

    static func encode(_ codes: [String]) -> String {
        codes.joined(separator: ",")
    }

    /// `Tiếng Việt, English` — or `fallback` for an empty list.
    static func summary(_ codes: [String], fallback: String) -> String {
        let names = codes.compactMap(MovieLanguage.endonym)
        return names.isEmpty ? fallback : names.formatted(.list(type: .and, width: .narrow))
    }

    private static func decode(_ stored: String?) -> [String]? {
        guard let stored else { return nil }
        var seen = Set<String>()
        return stored.split(separator: ",").compactMap { MovieLanguage.code(String($0)) }.filter { seen.insert($0).inserted }
    }
}
