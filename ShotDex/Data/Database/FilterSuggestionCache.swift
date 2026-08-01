import Foundation

/// Shared autocomplete sources for Library search/filter and rule builders.
/// The DISTINCT scans run on this actor once, then every input surface reuses
/// the immutable catalog until an index run explicitly refreshes it.
struct FilterSuggestionCatalog: Sendable {
    var brands: [String]
    var bodies: [String]
    var lenses: [String]
    /// Reverse-geocoded place names present in the library, most-photographed
    /// first. Also the vocabulary that lets the search parser recognise "fukuoka"
    /// as a place without guessing from the shape of the word.
    var places: [String]

    init(brands: [String] = [], bodies: [String] = [], lenses: [String] = [], places: [String] = []) {
        self.brands = brands
        self.bodies = bodies
        self.lenses = lenses
        self.places = places
    }

    static let empty = FilterSuggestionCatalog()
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
            lenses: (try? libraryQueries.distinctLenses()) ?? [],
            places: (try? libraryQueries.distinctPlaceTerms()) ?? []
        )
        cached = catalog
        return catalog
    }
}
