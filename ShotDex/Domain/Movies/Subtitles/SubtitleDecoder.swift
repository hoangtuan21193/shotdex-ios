import Foundation

/// Turns subtitle file bytes into text (FS-23.03 §3): a byte-order mark
/// wins, then strict UTF-8, then Foundation's detector over the encodings
/// subtitles are actually written in, steered by the subtitle's language
/// when known. A wrong guess is fixed by hand (⋯ › Encoding) through
/// `decode(_:encoding:)`.
enum SubtitleDecoder {
    struct Decoded: Equatable, Sendable {
        var text: String
        /// IANA name (`utf-8`, `windows-1258`) — stored on the subtitle row.
        var encoding: String
    }

    /// What the ⋯ › Encoding menu offers, IANA names.
    static let choices = [
        "utf-8", "utf-16", "windows-1258", "windows-1252", "iso-8859-1", "windows-1251", "windows-1250",
        "gb18030", "big5", "shift_jis", "euc-kr", "windows-1256", "windows-1255", "windows-1253", "windows-874",
    ]

    /// Language → its usual legacy encoding, tried first.
    private static let legacyByLanguage: [String: String] = [
        "vi": "windows-1258", "zh": "gb18030", "ja": "shift_jis", "ko": "euc-kr", "ru": "windows-1251",
        "uk": "windows-1251", "pl": "windows-1250", "cs": "windows-1250", "hu": "windows-1250", "ar": "windows-1256",
        "he": "windows-1255", "el": "windows-1253", "th": "windows-874",
    ]

    static func decode(_ data: Data, languageHint: String? = nil) -> Decoded {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return Decoded(text: normalize(text), encoding: "utf-8")
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return Decoded(text: normalize(text), encoding: "utf-16")
        }
        if let text = String(data: data, encoding: .utf8) {
            return Decoded(text: normalize(text), encoding: "utf-8")
        }
        let language = languageHint.map { String($0.prefix(2)).lowercased() }
        if let language, let preferred = legacyByLanguage[language], let text = decode(data, encoding: preferred) {
            return Decoded(text: text, encoding: preferred)
        }
        var converted: NSString?
        var lossy = ObjCBool(false)
        var options: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: choices.compactMap(nsEncoding).map(NSNumber.init(value:)),
            .useOnlySuggestedEncodingsKey: true,
            .allowLossyKey: false,
        ]
        if let language { options[.likelyLanguageKey] = language }
        let found = NSString.stringEncoding(for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: &lossy)
        if found != 0, let converted, let name = ianaName(found) {
            return Decoded(text: normalize(converted as String), encoding: name)
        }
        // Every byte means something in Latin-1: never nothing on screen.
        return Decoded(text: normalize(String(data: data, encoding: .isoLatin1) ?? ""), encoding: "iso-8859-1")
    }

    /// The user's pick; nil when the bytes are not valid in it.
    static func decode(_ data: Data, encoding name: String) -> String? {
        if name == "utf-8" { return String(data: data, encoding: .utf8).map(normalize) }
        guard let raw = nsEncoding(name), let text = String(data: data, encoding: String.Encoding(rawValue: raw)) else { return nil }
        return normalize(text)
    }

    /// Precomposed (NFC): Windows-1258 writes tone marks as combining
    /// characters, which would otherwise compare and wrap differently.
    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    private static func nsEncoding(_ iana: String) -> UInt? {
        let cf = CFStringConvertIANACharSetNameToEncoding(iana as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return CFStringConvertEncodingToNSStringEncoding(cf)
    }

    private static func ianaName(_ ns: UInt) -> String? {
        let cf = CFStringConvertNSStringEncodingToEncoding(ns)
        return (CFStringConvertEncodingToIANACharSetName(cf) as String?)?.lowercased()
    }
}
