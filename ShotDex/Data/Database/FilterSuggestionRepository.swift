import Foundation

/// Shared autocomplete sources for Library search/filter and rule builders.
/// The DISTINCT scans run on this actor once, then every input surface reuses
/// the immutable catalog until an index run explicitly refreshes it.
struct FilterSuggestionCatalog: Sendable {
    var brands: [String]
    var bodies: [String]
    var lenses: [String]

    static let empty = FilterSuggestionCatalog(brands: [], bodies: [], lenses: [])
}

actor FilterSuggestionRepository {
    private let queryDAO: LibraryQueryDAO
    private var cached: FilterSuggestionCatalog?

    init(queryDAO: LibraryQueryDAO) {
        self.queryDAO = queryDAO
    }

    func load(forceRefresh: Bool = false) -> FilterSuggestionCatalog {
        if !forceRefresh, let cached {
            return cached
        }
        let catalog = FilterSuggestionCatalog(
            brands: (try? queryDAO.distinctCameraBrands()) ?? [],
            bodies: (try? queryDAO.distinctCameraBodies()) ?? [],
            lenses: (try? queryDAO.distinctLenses()) ?? []
        )
        cached = catalog
        return catalog
    }
}
