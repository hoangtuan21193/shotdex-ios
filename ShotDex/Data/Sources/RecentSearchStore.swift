import Foundation

/// The queries the user ran recently, newest first.
///
/// `UserDefaults` rather than a table: this is a handful of short strings that
/// belongs to the person using the app, not to the indexed library — a database
/// migration for it would buy nothing, and it must survive a DEBUG re-index
/// (which erases the database on schema change).
@MainActor
@Observable
final class RecentSearchStore {
    /// Photos keeps its recents list short; past a handful the list stops being
    /// "what I was just doing" and starts being history nobody reads.
    /// Nonisolated so `merged` can default to it and tests can read it off the main
    /// actor; it is a constant, so there is nothing to isolate.
    nonisolated static let limit = 10

    private let defaults: UserDefaults
    private let key: String

    private(set) var queries: [String]

    init(defaults: UserDefaults = .standard, key: String = "search.recentQueries") {
        self.defaults = defaults
        self.key = key
        queries = (defaults.array(forKey: key) as? [String]) ?? []
    }

    /// Records a query as the newest entry. Re-running an old query moves it to the
    /// top instead of duplicating it.
    func remember(_ rawQuery: String) {
        let merged = Self.merged(queries, with: rawQuery)
        guard merged != queries else { return }
        queries = merged
        defaults.set(merged, forKey: key)
    }

    func clear() {
        guard !queries.isEmpty else { return }
        queries = []
        defaults.removeObject(forKey: key)
    }

    /// Pure list rule, so the ordering and de-duplication are testable without
    /// touching `UserDefaults`.
    ///
    /// Case-insensitive de-duplication keeps the newly typed spelling: the user
    /// just wrote it, so it is the one they will recognise.
    nonisolated static func merged(
        _ existing: [String],
        with rawQuery: String,
        limit: Int = limit
    ) -> [String] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        let folded = trimmed.lowercased()
        var result = [trimmed]
        result.append(contentsOf: existing.filter { $0.lowercased() != folded })
        return Array(result.prefix(limit))
    }
}
