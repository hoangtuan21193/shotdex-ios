import Foundation

/// A reverse-geocoded address, in the pieces search and display each need.
struct ResolvedPlace: Equatable, Sendable {
    /// Point of interest or street name — the most specific label available.
    var name: String?
    var subLocality: String?
    var locality: String?
    var adminArea: String?
    var country: String?
    var countryCode: String?
    /// Everything on one line, for the metadata panel.
    var address: String?

    init(
        name: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        adminArea: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        address: String? = nil
    ) {
        self.name = name
        self.subLocality = subLocality
        self.locality = locality
        self.adminArea = adminArea
        self.country = country
        self.countryCode = countryCode
        self.address = address
    }

    /// Whether the geocoder said anything worth storing.
    var isEmpty: Bool {
        PlaceSearchText.components(of: self).isEmpty
    }

    /// Shortest label that still identifies the place, for a chip or a row.
    var displayTitle: String? {
        PlaceSearchText.firstNonempty([name, locality, subLocality, adminArea, country])
    }
}

/// Builds the single column place search matches against, and normalizes the
/// terms that get matched against it.
///
/// Both sides go through `normalized`, which is what makes "da nang" find
/// "Đà Nẵng" and "fukuoka" find "Fukuoka-shi": lowercased, stripped of
/// diacritics, punctuation turned into spaces. Doing it at write time means the
/// query is a plain `LIKE` — no per-row folding, no collation surprises.
enum PlaceSearchText {
    /// The column value: every distinct component, normalized, joined by spaces.
    static func build(from place: ResolvedPlace) -> String? {
        let joined = components(of: place)
            .map(normalized)
            .filter { !$0.isEmpty }
        guard !joined.isEmpty else { return nil }
        // A component often repeats another ("Fukuoka" as both city and
        // prefecture); duplicates would only pad the column.
        var seen = Set<String>()
        let unique = joined.filter { seen.insert($0).inserted }
        return unique.joined(separator: " ")
    }

    /// Letters that diacritic folding leaves alone because they are letters in
    /// their own right rather than a base plus a mark. `Đ` is the one that
    /// matters here: without this, "da nang" does not find "Đà Nẵng" — folding
    /// turns "Nẵng" into "Nang" but leaves "Đà" as "đa".
    private static let irreducibleLetters: [Character: String] = [
        "đ": "d", "ð": "d", "ø": "o", "ł": "l", "þ": "th",
        "ß": "ss", "æ": "ae", "œ": "oe", "ı": "i",
    ]

    /// Normalizes one side of a comparison. Must be used for the stored column
    /// *and* for the search term, or the two stop matching.
    static func normalized(_ text: String) -> String {
        let lowered = text.lowercased()
        let expanded = String(
            lowered.flatMap { character in
                irreducibleLetters[character].map(Array.init) ?? [character]
            }
        )
        let folded = expanded.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        // Commas, hyphens and slashes separate address parts rather than words,
        // so they become spaces instead of being glued to a neighbour.
        let separated = folded.map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }
        return String(separated)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    static func components(of place: ResolvedPlace) -> [String] {
        [
            place.name,
            place.subLocality,
            place.locality,
            place.adminArea,
            place.country,
            place.countryCode,
            // The one-line address goes in too. iOS 26's reverse geocoder returns
            // far fewer structured fields than `CLPlacemark` did, and without this
            // a ward or a country would only be searchable on older systems.
            // Duplicates are dropped below, so the overlap costs nothing.
            place.address,
        ]
        .compactMap { $0 }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static func firstNonempty(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
