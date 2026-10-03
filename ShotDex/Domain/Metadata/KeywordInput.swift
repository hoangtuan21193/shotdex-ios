import Foundation

/// Photos' own caption and keywords of one asset (iOS 27,
/// `PHAsset.extendedMetadata`) — what the app mirrors to filter on
/// (FS-02.07 §8). Photos is the source of truth; this is a copy.
struct CaptionKeywords: Equatable, Hashable, Sendable {
    /// Nil when the asset has no caption; never an empty string.
    var caption: String?
    var keywords: [String]

    init(caption: String? = nil, keywords: [String] = []) {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.caption = (trimmed?.isEmpty ?? true) ? nil : caption
        self.keywords = keywords
    }

    static let empty = CaptionKeywords()

    var isEmpty: Bool { caption == nil && keywords.isEmpty }
}

/// One keyword the library already uses: its most common spelling and how
/// many photos carry any spelling of it — what the Add Keyword suggestions
/// and the search parser's vocabulary are built from (FS-02.07 §4, §7).
struct KeywordCount: Equatable, Hashable, Sendable {
    var keyword: String
    var count: Int
}

/// What the user types into a keyword field, turned into the keywords that
/// get written (FS-02.07 §4). Pure.
///
/// Two keys, because the spec asks two different questions:
/// - `caseKey` folds **case only** — `Sunset` and `sunset` are one keyword
///   (no duplicate in another case is ever created), but `Đà Lạt` and
///   `Da Lat` stay two;
/// - `foldKey` folds case **and** diacritics, the way place search does —
///   what suggestions, filters and search match on, so typing `da lat`
///   finds both.
enum KeywordInput {
    static func caseKey(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func foldKey(_ text: String) -> String {
        PlaceSearchText.normalized(text)
    }

    /// `beach, family` is two keywords: split on commas, trim both ends,
    /// drop empty pieces and repeats of a piece already given (in any case).
    static func split(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(caseKey($0)).inserted }
    }

    /// The spelling to write for what was typed: the library's own spelling
    /// when one exists in another case (`sunset` → `Sunset`), the typed text
    /// otherwise. `existing` maps `caseKey` to the spelling in use.
    static func spelling(for typed: String, existing: [String: String]) -> String {
        existing[caseKey(typed)] ?? typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `split` then `spelling` for each piece — the keywords one Return adds.
    static func keywords(from text: String, existing: [String: String]) -> [String] {
        split(text).map { spelling(for: $0, existing: existing) }
    }

    /// Up to `limit` library keywords matching a fragment, most photos first
    /// (FS-02.07 §4). Matching ignores case and diacritics; a keyword the
    /// photo already has is left out. An empty fragment suggests nothing.
    static func suggestions(
        for fragment: String,
        in catalog: [KeywordCount],
        excluding present: [String] = [],
        limit: Int = 8
    ) -> [KeywordCount] {
        let needle = foldKey(fragment)
        guard !needle.isEmpty else { return [] }
        let skip = Set(present.map(caseKey))
        let matches = catalog.filter {
            !skip.contains(caseKey($0.keyword)) && foldKey($0.keyword).contains(needle)
        }
        return Array(
            matches
                .sorted {
                    if $0.count != $1.count { return $0.count > $1.count }
                    return $0.keyword.localizedStandardCompare($1.keyword) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    /// `caseKey` → spelling, from the library's keyword counts.
    static func spellings(_ catalog: [KeywordCount]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in catalog where result[caseKey(entry.keyword)] == nil {
            result[caseKey(entry.keyword)] = entry.keyword
        }
        return result
    }
}
