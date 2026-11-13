import Foundation
import Observation

/// What the search screen shows while the user types — suggestions with counts
/// and the matching photos right under them (FS-01.03c §2–§4) — shared by the
/// iOS 26 search tab, the pre-26 sheet and the Mac window.
///
/// Every keystroke cancels the previous update and starts a new one after
/// `debounce`; all reads run on GRDB's reader pool, never on the main actor
/// (A2). The language model is never asked while typing — only on the Search
/// key, as before (FS-01.03 §4).
@MainActor
@Observable
final class SearchSession {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            if modelReading?.text != trimmedText { modelReading = nil }
            scheduleUpdate()
        }
    }

    var tokens: [SearchToken] = [] {
        didSet {
            guard tokens != oldValue else { return }
            scheduleUpdate()
        }
    }

    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: [LibraryGridItem] = []
    private(set) var resultCount = 0
    /// Whether `results` belongs to the current input, so an empty grid can
    /// say No Results instead of flashing it while the first read runs.
    private(set) var hasResults = false
    /// The empty field's *In Your Library* rows (FS-01.03c §5).
    private(set) var highlights: [SearchGroup] = []
    /// Set when the Search key had a model read the sentence; the results then
    /// come from its rules until the text changes.
    private(set) var modelReading: (text: String, query: SmartAlbumQuery)?

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasInput: Bool { !tokens.isEmpty || !trimmedText.isEmpty }
    /// The tokens and the text as words — what Recents remembers.
    var displayText: String {
        (tokens.map(\.name) + (trimmedText.isEmpty ? [] : [trimmedText])).joined(separator: " ")
    }

    static let debounce = Duration.milliseconds(150)
    /// The first page of results, drawn before the rest is read (A5).
    static let firstBatch = 300
    static let suggestionLimit = 8

    private let index: SearchIndexQueries
    private let library: LibraryQueries
    let service: SearchService
    private var updateTask: Task<Void, Never>?
    private var spellingCandidates: [SearchGroup]?

    init(index: SearchIndexQueries, library: LibraryQueries, service: SearchService) {
        self.index = index
        self.library = library
        self.service = service
    }

    // MARK: Input

    /// Picks a suggestion: it becomes a token and the typed text goes, the way
    /// Photos turns a suggestion into a token (FS-01.03c §3).
    func choose(_ suggestion: SearchSuggestion) {
        switch suggestion {
        case .group(let group), .didYouMean(let group):
            tokens.append(SearchToken(group: group))
        case .interpretation(let label, let rules):
            tokens.append(SearchToken(name: label, symbol: "text.magnifyingglass", rules: rules))
        }
        text = ""
    }

    func choose(_ group: SearchGroup) { choose(.group(group)) }

    /// Clears everything, as leaving the tab does.
    func reset() {
        updateTask?.cancel()
        text = ""
        tokens = []
        suggestions = []
        results = []
        resultCount = 0
        hasResults = false
        modelReading = nil
    }

    /// The Search key: keep the results, remember the search, and let a model
    /// read a sentence the parser only half understood (FS-01.03c §4).
    func submit() async {
        guard hasInput else { return }
        service.recentSearches.remember(displayText)
        let typed = trimmedText
        guard !typed.isEmpty, service.supportsNaturalLanguage else { return }
        let local = await service.resolveLocally(typed)
        if local.hasRules, local.query.validRules.allSatisfy({ $0.field != .anyText }) { return }
        let resolution = await service.resolve(typed)
        guard resolution.usedModel, typed == trimmedText else { return }
        modelReading = (typed, resolution.query)
        scheduleUpdate(immediately: true)
    }

    /// Remembers the current search — when a result is opened, or the search is
    /// taken to Library.
    func remember() {
        guard hasInput else { return }
        service.recentSearches.remember(displayText)
    }

    /// Everything the field holds as one rule query: the tokens, then what the
    /// parser (or the model, after Search) read from the text. Words nothing
    /// understood search like free text, each its own `anyText` rule.
    func currentQuery() async -> SmartAlbumQuery {
        if let shown, shown.input == inputKey { return shown.query }
        return await Self.query(tokens: tokens, text: trimmedText, modelReading: modelReading, service: service)
    }

    /// The query the results on screen came from, with the input it was for —
    /// so Open in Library takes exactly what the user is looking at.
    @ObservationIgnored private var shown: (input: String, query: SmartAlbumQuery)?

    private var inputKey: String {
        tokens.map(\.id.uuidString).joined(separator: ",") + "|" + trimmedText
    }

    private static func query(
        tokens: [SearchToken], text: String,
        modelReading: (text: String, query: SmartAlbumQuery)?, service: SearchService
    ) async -> SmartAlbumQuery {
        if let modelReading, !text.isEmpty, modelReading.text == text {
            var query = SmartAlbumQuery(matchMode: .all, rules: tokens.flatMap(\.rules))
            query.rules += modelReading.query.rules
            query.groups += modelReading.query.groups
            return query
        }
        return await service.query(tokens: tokens, text: text)
    }

    // MARK: Empty field

    func loadHighlights() async {
        let groups = (try? await index.groups(in: [.camera, .lens, .place, .year])) ?? []
        highlights = SearchSuggestionRanker.libraryHighlights(groups)
    }

    // MARK: Updates

    private func scheduleUpdate(immediately: Bool = false) {
        updateTask?.cancel()
        guard hasInput else {
            suggestions = []
            results = []
            resultCount = 0
            hasResults = false
            return
        }
        let text = trimmedText
        let tokens = tokens
        let modelReading = modelReading
        updateTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: Self.debounce) }
            guard !Task.isCancelled else { return }
            await self?.refresh(text: text, tokens: tokens, modelReading: modelReading)
        }
    }

    private func refresh(text: String, tokens: [SearchToken], modelReading: (text: String, query: SmartAlbumQuery)?) async {
        let rows = await suggestionRows(text: text, tokens: tokens)
        guard !Task.isCancelled else { return }
        var query = await Self.query(tokens: tokens, text: text, modelReading: modelReading, service: service)
        if modelReading == nil, !text.isEmpty {
            query = await widened(query, tokens: tokens, text: text, rows: rows)
        }
        guard !Task.isCancelled else { return }
        let first = (try? await library.gridItems(matching: query, sort: .dateTakenNewest, limit: Self.firstBatch)) ?? []
        guard !Task.isCancelled else { return }
        let count = first.count < Self.firstBatch
            ? first.count
            : ((try? await library.count(matching: query)) ?? first.count)
        guard !Task.isCancelled else { return }
        var shown = rows
        if shown.isEmpty, count == 0, !text.isEmpty, let near = await spellingSuggestion(for: text) {
            shown = [.didYouMean(near)]
        }
        guard !Task.isCancelled else { return }
        suggestions = shown
        self.shown = (tokens.map(\.id.uuidString).joined(separator: ",") + "|" + text, query)
        results = first
        resultCount = count
        hasResults = true
        if count > first.count {
            let all = (try? await library.gridItems(matching: query, sort: .dateTakenNewest)) ?? first
            guard !Task.isCancelled else { return }
            results = all
        }
    }

    /// Half a word (`iso`, `can`) is free text to the parser and matches
    /// almost nothing as such. Like Photos, the photos shown are those of the
    /// text **or** of any suggestion on screen — so `iso` shows every photo of
    /// the ISO values listed above it (FS-01.03c §4).
    private func widened(_ query: SmartAlbumQuery, tokens: [SearchToken], text: String, rows: [SearchSuggestion]) async -> SmartAlbumQuery {
        let local = await service.resolveLocally(text)
        guard !local.hasRules else { return query }
        let matched = rows.compactMap { row -> SmartAlbumRule? in
            if case .group(let group) = row { return group.rule }
            return nil
        }
        guard !matched.isEmpty else { return query }
        var widened = SmartAlbumQuery(matchMode: .all, rules: tokens.flatMap(\.rules))
        let typed = SmartAlbumRule(field: .anyText, op: .contains, text: local.searchText ?? text)
        widened.groups = [SmartAlbumRuleGroup(matchMode: .any, rules: [typed] + matched)]
        return widened
    }

    private func suggestionRows(text: String, tokens: [SearchToken]) async -> [SearchSuggestion] {
        guard !text.isEmpty else { return [] }
        var groups = (try? await index.groups(matching: text)) ?? []
        let read = await service.interpretationRules(text)
        let chosen = Set(tokens.flatMap(\.rules).map(Self.ruleKey))
        groups.removeAll { chosen.contains(Self.ruleKey($0.rule)) }
        if !tokens.isEmpty, !groups.isEmpty {
            let scope = SmartAlbumQuery(matchMode: .all, rules: tokens.flatMap(\.rules))
            if let counts = try? await index.counts(of: groups, within: scope) {
                groups = groups.map { group in
                    var scoped = group
                    scoped.count = counts[group.id] ?? 0
                    return scoped
                }
            }
        }
        var rows: [SearchSuggestion] = []
        if Self.showsInterpretation(read, groupKeys: Set(groups.map { Self.ruleKey($0.rule) })) {
            rows.append(.interpretation(text: read.map(\.compactDisplaySummary).joined(separator: " · "), rules: read))
        }
        rows += SearchSuggestionRanker.rank(groups, typed: text, limit: Self.suggestionLimit - rows.count).map(SearchSuggestion.group)
        return rows
    }

    /// A row for what the parser read only when no single value already says
    /// it (FS-01.03c §2): two conditions or more (`85mm night`), or one that no
    /// group is — a comparison, a named period, a partial name.
    static func showsInterpretation(_ rules: [SmartAlbumRule], groupKeys: Set<String>) -> Bool {
        guard let first = rules.first else { return false }
        if rules.count >= 2 { return true }
        if groupKeys.contains(ruleKey(first)) { return false }
        // One exact value is what the matching rows already offer.
        let exact: Set<RuleOperator> = [.isExactly, .equalTo, .hasKeyword, .inMonth, .contains]
        return !exact.contains(first.op)
    }

    private static func ruleKey(_ rule: SmartAlbumRule) -> String {
        "\(rule.field.rawValue)|\(rule.op.rawValue)|\(rule.text)|\(rule.number ?? -1)|\(rule.numberUpper ?? -1)"
    }

    private func spellingSuggestion(for text: String) async -> SearchGroup? {
        if spellingCandidates == nil {
            spellingCandidates = (try? await index.groups(in: [.camera, .cameraBrand, .lens, .place, .keyword])) ?? []
        }
        return SearchSpelling.suggestion(for: text, in: spellingCandidates ?? [])
    }
}
