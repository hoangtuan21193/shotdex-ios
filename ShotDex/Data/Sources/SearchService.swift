import Foundation

/// Turns what the user typed into something the grid can run.
///
/// One door, so the two search surfaces (`SearchTab` on iOS 26, `SearchSheet`
/// before it) cannot drift apart, and so the order of attempts lives in one place:
///
/// 1. **The parser**, always. It is instant and exact, and it covers the
///    shorthands people actually type — `85mm`, `f > 1.2`, `iso trên 3200`,
///    `fukuoka`. If it understood the whole query there is nothing to gain from
///    asking a model.
/// 2. **The model**, only when the parser came back with nothing or left words
///    over, and only on a device that has one. It handles sentences.
/// 3. **Free text**, if neither produced a rule — the behaviour the app has always
///    had, so nothing that used to work stops working.
@MainActor
@Observable
final class SearchService {
    /// The interpretation of a query, ready to apply.
    struct Resolution: Equatable, Sendable {
        /// Conditions to install as the grid's advanced query. Empty means none.
        var query = SmartAlbumQuery.empty
        /// Text to search the old way, when there is no rule for it.
        var searchText: String?
        /// Whether a model produced any of this, for the interpretation row.
        var usedModel = false

        var hasRules: Bool { !query.isEmpty }
    }

    private let filterSuggestions: FilterSuggestionCache

    /// The queries the user ran before. Lives here because this is the one place
    /// every surface goes through to run a search, so nothing can search without
    /// being remembered, and both surfaces read one list.
    let recentSearches: RecentSearchStore

    /// The model the AI Search row names (FS-08.07 §5), asked fresh each
    /// time so a change in Settings applies to the next search. nil: Off,
    /// or nothing on the device or at home can do it.
    private let model: @MainActor () -> (any SearchModel)?

    /// Whether a sentence can be read now.
    var supportsNaturalLanguage: Bool { model() != nil }

    init(
        filterSuggestions: FilterSuggestionCache,
        recentSearches: RecentSearchStore,
        model: @escaping @MainActor () -> (any SearchModel)? = { nil }
    ) {
        self.filterSuggestions = filterSuggestions
        self.recentSearches = recentSearches
        self.model = model
    }

    /// Loads the model in the background when the search screen opens, so the first
    /// query does not pay for it.
    func prepare() {
        guard let model = model() else { return }
        Task {
            let vocabulary = await filterSuggestions.load()
            await model.prewarm(vocabulary: vocabulary)
        }
    }

    /// The model's rules, or nil once its time is up — the parser's answer
    /// then stands and nothing says a model was tried (§5).
    static func ask(_ model: any SearchModel, _ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]? {
        await withTaskGroup(of: [SmartAlbumRule]?.self) { group in
            group.addTask { await model.translate(query, vocabulary: vocabulary) }
            group.addTask {
                try? await Task.sleep(for: model.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// How the parser reads a query, as chip-sized fragments, for the suggestion
    /// popup over the search field.
    ///
    /// Parser only — never the model. This runs on every keystroke, so it has to be
    /// instant and free; the model runs once, when the query is applied.
    func preview(_ rawQuery: String, now: Date = Date()) async -> [String] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return [] }
        let vocabulary = await filterSuggestions.load()
        return SearchIntentParser.parse(trimmed, vocabulary: vocabulary, now: now)
            .query.validRules
            .map(\.compactDisplaySummary)
    }

    /// Resolves a query with the parser alone.
    ///
    /// For callers that must not pay for the model: the recents strip resolves
    /// three queries every time the search screen opens, and a 2-second model call
    /// each would be paid before anything is on screen.
    func resolveLocally(_ rawQuery: String, now: Date = Date()) async -> Resolution {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Resolution() }
        let vocabulary = await filterSuggestions.load()
        let parsed = SearchIntentParser.parse(trimmed, vocabulary: vocabulary, now: now)
        guard parsed.isConfident else { return Resolution(searchText: trimmed) }
        var query = parsed.query
        query.rules.append(contentsOf: Self.leftoverRules(parsed.leftoverText))
        return Resolution(query: query, searchText: nil)
    }

    /// The words a partly understood search left over, one `anyText` rule
    /// each: they match what plain text search matches — camera, lens,
    /// filename, caption, keyword — not the filename alone (FS-02.07 §7,
    /// decided 2026-10-03), and each stays a chip the user can delete.
    static func leftoverRules(_ leftover: String?) -> [SmartAlbumRule] {
        guard let leftover else { return [] }
        return leftover.split(separator: " ").map {
            SmartAlbumRule(field: .anyText, op: .contains, text: String($0))
        }
    }

    /// Resolves a query. Never throws and never returns nothing: the worst case is
    /// the free-text path.
    func resolve(_ rawQuery: String, now: Date = Date()) async -> Resolution {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Resolution() }

        let vocabulary = await filterSuggestions.load()
        let parsed = SearchIntentParser.parse(trimmed, vocabulary: vocabulary, now: now)

        // Fully understood: apply it and stop. Asking a model to re-read "85mm"
        // would only add latency and a chance of a worse answer.
        if parsed.isConfident, parsed.leftoverText == nil {
            return Resolution(query: parsed.query, searchText: nil)
        }

        if let model = model(),
           let rules = await Self.ask(model, trimmed, vocabulary: vocabulary),
           !rules.isEmpty {
            return Resolution(
                query: SmartAlbumQuery(matchMode: .all, rules: rules),
                searchText: nil,
                usedModel: true
            )
        }

        // A partial parse still beats plain text: "fukuoka wedding" keeps the
        // place condition and looks for the rest wherever free text looks —
        // camera, lens, filename, caption, keyword.
        //
        // The leftover becomes a rule rather than staying free text because the
        // grid takes one or the other — `LibraryModel.criteria` and
        // `advancedQuery` clear each other — and a chip the user can see and
        // delete beats a word that silently narrowed the results or was
        // silently dropped.
        if parsed.isConfident {
            var query = parsed.query
            query.rules.append(contentsOf: Self.leftoverRules(parsed.leftoverText))
            return Resolution(query: query, searchText: nil)
        }
        return Resolution(searchText: trimmed)
    }

}
