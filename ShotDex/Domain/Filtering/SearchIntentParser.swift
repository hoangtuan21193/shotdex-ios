import Foundation

/// What a typed query turned out to mean.
struct SearchIntent: Equatable, Sendable {
    /// Conditions the query expressed. Empty when nothing was recognised.
    var query = SmartAlbumQuery.empty
    /// Words that meant nothing to the parser, kept so the old free-text search
    /// still gets its chance — a filename or a camera the library has not indexed
    /// yet has no rule to become.
    var leftoverText: String?

    /// Whether there is a rule to apply. The caller uses this to decide between
    /// the rule path (chips) and plain text search.
    var isConfident: Bool { !query.isEmpty }

    static let empty = SearchIntent()
}

/// Turns "f lớn hơn 1.2", "iso trên 3200 chụp trước 2020" or "fukuoka" into
/// `SmartAlbumRule`s. Pure logic: no SwiftUI, no FoundationModels, no clock.
///
/// This is the floor, not the ceiling. Apple's on-device model handles phrasings
/// nobody wrote a pattern for, but it needs iOS 26 and an Apple-Intelligence
/// device, so on most of the installed base this parser *is* the feature. It also
/// runs first for anything it recognises outright, because a table lookup beats
/// waiting on a language model for "85mm".
///
/// Vietnamese is handled by canonicalising it, not by a second grammar: multi-word
/// phrases collapse into the same tokens English produces ("lớn hơn" → `>`,
/// "khẩu độ" → `f`), and one scanner reads the result. Adding a phrase is one
/// table entry, and both languages get the same behaviour by construction.
enum SearchIntentParser {
    /// - Parameters:
    ///   - vocabulary: what the library actually contains. A bare word becomes a
    ///     place, camera or lens rule only if it is one of these, so the parser
    ///     never has to guess from the shape of a word.
    ///   - now: reference date for "yesterday", "last month". Passed in, never
    ///     read from the clock, so tests are deterministic.
    static func parse(
        _ rawQuery: String,
        vocabulary: FilterSuggestionCatalog = .empty,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchIntent {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let tokens = canonicalTokens(trimmed)
        guard !tokens.isEmpty else { return .empty }

        var rules: [SmartAlbumRule] = []
        var leftovers: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if let consumed = matchRule(
                from: tokens,
                at: index,
                now: now,
                calendar: calendar,
                into: &rules
            ) {
                index += consumed
                continue
            }
            leftovers.append(token.original)
            index += 1
        }

        // Whatever is left is a name: a place the library knows, a camera, a lens.
        let names = nameRules(from: leftovers, vocabulary: vocabulary)
        rules.append(contentsOf: names.rules)

        var intent = SearchIntent()
        intent.query = SmartAlbumQuery(matchMode: .all, rules: rules)
        let leftoverText = names.unmatched.joined(separator: " ")
        intent.leftoverText = leftoverText.isEmpty ? nil : leftoverText
        return intent
    }

    // MARK: Tokens

    /// One token, in both the form the scanner reads and the form the user typed
    /// (needed for place and camera names, which go into rules verbatim).
    struct Token: Equatable, Sendable {
        var canonical: String
        var original: String
    }

    /// Multi-word phrases that mean one token.
    ///
    /// Matched against **runs of whole words**, never as substrings. Substring
    /// matching looked simpler and was silently wrong: "tu" (từ, "from") is inside
    /// "aperture", so "aperture over 1.2" became "aper from re over 1.2" and the
    /// query fell apart. Single words belong in `words`, not here.
    private static let phrases: [String: String] = [
        // Comparisons
        "lon hon hoac bang": ">=", "nho hon hoac bang": "<=",
        "greater than or equal": ">=", "less than or equal": "<=",
        "lon hon": ">", "nho hon": "<", "cao hon": ">", "thap hon": "<",
        "nhanh hon": "faster", "cham hon": "slower",
        "faster than": "faster", "slower than": "slower",
        "greater than": ">", "more than": ">", "less than": "<",
        "at least": ">=", "at most": "<=",
        // Fields
        "khau do": "f", "tieu cu": "focal", "do dai tieu cu": "focal",
        "toc do man tran": "shutter", "toc do": "shutter",
        "focal length": "focal", "shutter speed": "shutter",
        "ong kinh": "lens", "may anh": "camera",
        // Favorite
        "yeu thich": "favorite", "da thich": "favorite", "anh thich": "favorite",
        // Dates
        "hom nay": "today", "hom qua": "yesterday",
        "tuan nay": "thisweek", "tuan truoc": "lastweek",
        "thang nay": "thismonth", "thang truoc": "lastmonth",
        "nam nay": "thisyear", "nam ngoai": "lastyear",
        "this week": "thisweek", "last week": "lastweek",
        "this month": "thismonth", "last month": "lastmonth",
        "this year": "thisyear", "last year": "lastyear",
        "ngay qua": "daysago", "ngay gan day": "daysago", "days ago": "daysago",
        "thang qua": "monthsago", "months ago": "monthsago",
        // Sensor formats written as more than one word.
        "full frame": "fullframe", "micro four thirds": "mft",
        "medium format": "mediumformat", "1 inch": "1inch",
    ]

    /// The longest phrase, in words — how far ahead the scanner has to look.
    private static let longestPhrase = 4

    /// Single words mapped onto the canonical vocabulary.
    private static let words: [String: String] = [
        "tren": ">", "duoi": "<", "over": ">", "above": ">", "under": "<", "below": "<",
        "min": ">=", "max": "<=",
        "aperture": "f", "khau": "f", "fstop": "f",
        "focal": "focal", "mm": "mm",
        "shutter": "shutter", "speed": "shutter",
        "iso": "iso",
        "favorite": "favorite", "favourite": "favorite", "starred": "favorite", "thich": "favorite",
        "truoc": "before", "before": "before", "sau": "after", "after": "after",
        "nam": "year", "year": "year",
        "today": "today", "yesterday": "yesterday",
        "last": "last", "qua": "last",
        "ngay": "day", "day": "day", "days": "day",
        "thang": "month", "month": "month", "months": "month",
        "tu": "from", "from": "from", "den": "to", "toi": "to", "to": "to", "and": "to",
    ]

    /// Folds a query into scanner tokens.
    ///
    /// Words are split first, folded individually, then phrases are matched over
    /// word runs — that order is what keeps a phrase from matching inside a word.
    /// Each token keeps what the user typed, because place and camera names go
    /// into rules verbatim and a chip should read "Fukuoka", not "fukuoka".
    static func canonicalTokens(_ query: String) -> [Token] {
        var raw: [String] = []
        for word in query.split(whereSeparator: { $0 == " " || $0 == "," }) {
            raw.append(contentsOf: splitSymbols(String(word)))
        }
        let folded = raw.map(fold)

        var tokens: [Token] = []
        var index = 0
        while index < folded.count {
            var matched = false
            let maximum = min(longestPhrase, folded.count - index)
            // Longest run first, so "lớn hơn hoặc bằng" is not eaten by "lớn hơn".
            for length in stride(from: maximum, through: 2, by: -1) {
                let phrase = folded[index..<(index + length)].joined(separator: " ")
                guard let canonical = phrases[phrase] else { continue }
                tokens.append(
                    Token(
                        canonical: canonical,
                        original: raw[index..<(index + length)].joined(separator: " ")
                    )
                )
                index += length
                matched = true
                break
            }
            if matched { continue }
            let word = folded[index]
            tokens.append(Token(canonical: words[word] ?? word, original: raw[index]))
            index += 1
        }
        return tokens
    }

    /// Separates comparison symbols from the value they are glued to, so "f>1.2"
    /// and "f > 1.2" reach the scanner identically. Dashes are normalized here too
    /// — an en dash between two numbers is a range, not a minus sign.
    private static func splitSymbols(_ word: String) -> [String] {
        var spaced = word
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2265}", with: ">=")
            .replacingOccurrences(of: "\u{2264}", with: "<=")
        spaced = spaced
            .replacingOccurrences(of: ">", with: " > ")
            .replacingOccurrences(of: "<", with: " < ")
        // The two lines above break ">=" into "> ="; rejoin it.
        spaced = spaced
            .replacingOccurrences(of: "> =", with: ">=")
            .replacingOccurrences(of: "< =", with: "<=")
        return spaced.split(separator: " ").map(String.init)
    }

    /// Lowercases and strips accents, so the tables can be written in plain ASCII.
    private static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    // MARK: Scanner

    /// Tries every rule shape at `index`. Returns how many tokens it consumed.
    private static func matchRule(
        from tokens: [Token],
        at index: Int,
        now: Date,
        calendar: Calendar,
        into rules: inout [SmartAlbumRule]
    ) -> Int? {
        if let (rule, consumed) = dateRule(tokens, index, now, calendar) {
            rules.append(rule)
            return consumed
        }
        if let (rule, consumed) = numericRule(tokens, index) {
            rules.append(rule)
            return consumed
        }
        if let (rule, consumed) = standaloneRule(tokens, index) {
            rules.append(rule)
            return consumed
        }
        return nil
    }

    /// `favorite`, `raw`, `full frame` — a single word that is a whole condition.
    private static func standaloneRule(_ tokens: [Token], _ index: Int) -> (SmartAlbumRule, Int)? {
        let token = tokens[index].canonical
        if token == "favorite" {
            return (SmartAlbumRule(field: .favorite, boolValue: true), 1)
        }
        if let format = sensorFormats[token] {
            return (SmartAlbumRule(field: .sensorFormat, op: .isExactly, text: format.rawValue), 1)
        }
        if let type = fileTypes[token] {
            return (SmartAlbumRule(field: .fileType, op: .isExactly, text: type.rawValue), 1)
        }
        return nil
    }

    private static let sensorFormats: [String: SensorFormat] = [
        "fullframe": .fullFrame, "ff": .fullFrame,
        "apsc": .apsC, "aps-c": .apsC, "apsh": .apsH, "aps-h": .apsH,
        "mft": .microFourThirds, "m43": .microFourThirds, "m4/3": .microFourThirds,
        "1inch": .oneInch, "1-inch": .oneInch,
        "mediumformat": .mediumFormat, "smartphone": .smartphone, "compact": .compact,
    ]

    private static let fileTypes: [String: PhotoFileType] = [
        "raw": .raw, "jpeg": .jpeg, "jpg": .jpeg, "heic": .heic, "heif": .heic,
        "png": .png, "tiff": .tiff, "tif": .tiff, "gif": .gif, "dng": .dng,
    ]
}
