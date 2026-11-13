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
/// this is capped at a handful of cards and resolves with the parser only.
@MainActor
@Observable
final class SearchRecentsModel {
    /// What Photos shows on a phone. Three cards is also what fits in one row
    /// without scrolling on the narrowest phone.
    nonisolated static let minimumCards = 3
    /// The most a wide screen shows (a 13" iPad at ~150pt a card). Loaded
    /// whatever the width, so a rotation or a resize never waits on queries.
    nonisolated static let maximumCards = 8
    /// About the size of a card where there is room for more than three: a
    /// wider screen gets more recents, not three 295pt cards that the keyboard
    /// cuts (DUO_LOOP 3c).
    nonisolated static let preferredCardWidth: CGFloat = 150

    /// How many cards one row of `width` holds with `spacing` between them —
    /// never fewer than three, never more than are loaded.
    nonisolated static func cardCount(width: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return minimumCards }
        let fits = Int(((width + spacing) / (preferredCardWidth + spacing)).rounded(.down))
        return min(maximumCards, max(minimumCards, fits))
    }

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

    /// Every stored query at once, on the reader pool (FS-01.03c §7, A4): one
    /// after another, ten `LIMIT 1` reads were the Search screen's opening
    /// pause. Order is kept; queries with no results are skipped, so a full
    /// strip may sit behind a few dead ones.
    private func load() async {
        let entries = store.queries
        let matches = await withTaskGroup(of: (Int, String?).self) { group in
            for (offset, entry) in entries.enumerated() {
                group.addTask { [weak self] in (offset, await self?.firstMatch(for: entry)) }
            }
            var found: [Int: String] = [:]
            for await (offset, assetId) in group {
                if let assetId { found[offset] = assetId }
            }
            return found
        }
        guard !Task.isCancelled else { return }
        cards = entries.enumerated()
            .compactMap { offset, entry in matches[offset].map { RecentSearchCard(query: entry, assetId: $0) } }
            .prefix(Self.maximumCards)
            .map { $0 }
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
