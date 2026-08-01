import Foundation

extension SearchIntentParser {
    /// Words that carry no condition — the glue of a sentence. Dropped rather than
    /// searched: "iso trên 3200 chụp trước 2020" must not also demand that some
    /// column contain "chụp", which would return nothing at all.
    static let stopWords: Set<String> = [
        // Vietnamese
        "chup", "anh", "hinh", "cai", "nhung", "cua", "voi", "bang", "o", "tai",
        "vao", "luc", "hoi", "la", "co", "va", "cho", "toi", "minh", "tim",
        // English
        "photo", "photos", "picture", "pictures", "shot", "shots", "taken",
        "with", "at", "in", "on", "the", "a", "an", "of", "my", "me", "find",
        "show", "all", "and", "from",
    ]

    /// Turns leftover words into place, camera and lens rules.
    ///
    /// Multi-word names are matched longest-run-first, so "Đà Nẵng" and
    /// "Canon EOS R6" survive as one condition instead of splitting into words
    /// that each match nothing.
    ///
    /// A word becomes a rule only when the library contains it. That is the whole
    /// trick behind "fukuoka" working: nothing about the string says it is a
    /// place, but the index does — so there is no heuristic to be wrong about, and
    /// a word the library has never seen falls through to free-text search exactly
    /// as it did before.
    static func nameRules(
        from words: [String],
        vocabulary: FilterSuggestionCatalog
    ) -> (rules: [SmartAlbumRule], unmatched: [String]) {
        let candidates = words.filter { word in
            let folded = PlaceSearchText.normalized(word)
            return !folded.isEmpty && !stopWords.contains(folded)
        }
        guard !candidates.isEmpty else { return ([], []) }

        let places = index(vocabulary.places)
        let bodies = index(vocabulary.bodies)
        let lenses = index(vocabulary.lenses)
        let brands = index(vocabulary.brands)

        var rules: [SmartAlbumRule] = []
        var unmatched: [String] = []
        var start = 0

        while start < candidates.count {
            var matched = false
            // Longest phrase first: three words, then two, then one.
            for length in stride(from: min(3, candidates.count - start), through: 1, by: -1) {
                let phrase = candidates[start..<(start + length)].joined(separator: " ")
                let folded = PlaceSearchText.normalized(phrase)
                guard let hit = lookup(
                    folded,
                    places: places,
                    bodies: bodies,
                    lenses: lenses,
                    brands: brands
                ) else { continue }
                rules.append(
                    SmartAlbumRule(field: hit.field, op: .contains, text: hit.value)
                )
                start += length
                matched = true
                break
            }
            if !matched {
                unmatched.append(candidates[start])
                start += 1
            }
        }
        return (rules, unmatched)
    }

    /// Folded form → the spelling to put in the rule, so a chip shows "Fukuoka"
    /// and not "fukuoka".
    private static func index(_ values: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for value in values {
            let folded = PlaceSearchText.normalized(value)
            guard !folded.isEmpty, result[folded] == nil else { continue }
            result[folded] = value
        }
        return result
    }

    /// Place before camera before lens before brand.
    ///
    /// Place wins ties because a place name is the specific thing the user typed;
    /// camera and lens names are already reachable through their own vocabulary
    /// and rarely collide with a city.
    private static func lookup(
        _ folded: String,
        places: [String: String],
        bodies: [String: String],
        lenses: [String: String],
        brands: [String: String]
    ) -> (field: RuleField, value: String)? {
        if let value = places[folded] { return (.place, value) }
        if let value = bodies[folded] { return (.cameraBody, value) }
        if let value = lenses[folded] { return (.lens, value) }
        if let value = brands[folded] { return (.cameraBrand, value) }
        // Not an exact name, but it may be part of one: "R6" for "Canon EOS R6",
        // "fukuoka" for "Fukuoka-shi". A `contains` rule on the term itself then
        // covers the whole family it names.
        for (dictionary, field) in [
            (places, RuleField.place), (bodies, .cameraBody), (lenses, .lens), (brands, .cameraBrand),
        ] {
            if dictionary.keys.contains(where: { isPartOfName($0, folded) }) {
                return (field, folded)
            }
        }
        return nil
    }

    /// Whether `term` names part of `name` — a whole word of it, or the start of
    /// one.
    ///
    /// Matching anywhere inside the string was wrong: `f 3200` is refused as an
    /// aperture (see `isPlausible`), and the leftover `f` then matched *inside*
    /// "fukuoka" and came back as a place. Word starts only, and a prefix has to be
    /// long enough to mean something — one or two letters sit at the start of half
    /// the names in any library, while a model name like "R6" is a whole word.
    private static func isPartOfName(_ name: String, _ term: String) -> Bool {
        let words = name.split(separator: " ")
        if words.contains(where: { $0 == term }) { return true }
        guard term.count >= 3 else { return false }
        return words.contains { $0.hasPrefix(term) }
    }
}
