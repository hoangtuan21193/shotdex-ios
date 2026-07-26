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

actor FilterSuggestionCache {
    private let libraryQueries: LibraryQueries
    private var cached: FilterSuggestionCatalog?

    init(libraryQueries: LibraryQueries) {
        self.libraryQueries = libraryQueries
    }

    func load(forceRefresh: Bool = false) -> FilterSuggestionCatalog {
        if !forceRefresh, let cached {
            return cached
        }
        let catalog = FilterSuggestionCatalog(
            brands: (try? libraryQueries.distinctCameraBrands()) ?? [],
            bodies: (try? libraryQueries.distinctCameraBodies()) ?? [],
            lenses: (try? libraryQueries.distinctLenses()) ?? []
        )
        cached = catalog
        return catalog
    }
}
