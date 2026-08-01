import Foundation

/// One recent query, with the newest photo it finds.
struct RecentSearchCard: Identifiable, Equatable, Sendable {
    /// What the user typed, and what a tap re-runs.
    let query: String
    /// First result, in the Library's newest-first order — the card's thumbnail.
    let assetId: String

    var id: String { query }
}

/// The recents strip on the search screen: recent queries that still find
/// something, each with a photo to show for it.
///
/// A recent search that returns nothing is worse than no recent search — it looks
/// like the app forgot the photos — so a query is dropped from the strip rather
/// than shown empty. That means every entry costs one `LIMIT 1` query, which is why
/// this is capped at three cards and resolves with the parser only.
@MainActor
@Observable
final class SearchRecentsModel {
    /// What Photos shows. Three cards is also what fits in one row without
    /// scrolling on the narrowest phone.
    static let maximumCards = 3

    private let store: RecentSearchStore
    private let service: SearchService
    private let libraryQueries: LibraryQueries

    private(set) var cards: [RecentSearchCard] = []
    private var loadTask: Task<Void, Never>?

    init(store: RecentSearchStore, service: SearchService, libraryQueries: LibraryQueries) {
        self.store = store
        self.service = service
        self.libraryQueries = libraryQueries
    }

    var isEmpty: Bool { cards.isEmpty }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load() }
    }

    func clear() {
        store.clear()
        cards = []
        loadTask?.cancel()
    }

    private func load() async {
        var result: [RecentSearchCard] = []
        // Walks more entries than it shows: the ones with no results are skipped,
        // so a full strip may sit behind a few dead queries.
        for entry in store.queries {
            if result.count == Self.maximumCards { break }
            if Task.isCancelled { return }
            guard let assetId = await firstMatch(for: entry) else { continue }
            result.append(RecentSearchCard(query: entry, assetId: assetId))
        }
        guard !Task.isCancelled else { return }
        cards = result
    }

    private func firstMatch(for text: String) async -> String? {
        let resolution = await service.resolveLocally(text)
        do {
            if resolution.hasRules {
                return try await libraryQueries.gridItems(
                    matching: resolution.query,
                    sort: .dateTakenNewest,
                    limit: 1
                ).first?.assetId
            }
            guard let searchText = resolution.searchText else { return nil }
            var criteria = FilterCriteria()
            criteria.searchText = searchText
            return try await libraryQueries.gridItems(
                matching: criteria,
                sort: .dateTakenNewest,
                limit: 1
            ).first?.assetId
        } catch {
            return nil
        }
    }
}
