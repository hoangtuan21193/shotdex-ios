import Foundation

/// Shared autocomplete sources for Library search/filter and rule builders.
/// The DISTINCT scans run on this actor once, then every input surface reuses
/// the immutable catalog until an index run explicitly refreshes it.
struct FilterSuggestionCatalog: Sendable {
    /// Changes whenever any list does, so the search parser can build its
    /// lookup tables once per catalog instead of on every keystroke
    /// (FS-01.03c §7, A3).
    private(set) var revision = UUID()

    var brands: [String] { didSet { revision = UUID() } }
    var bodies: [String] { didSet { revision = UUID() } }
    var lenses: [String] { didSet { revision = UUID() } }
    /// Reverse-geocoded place names present in the library, most-photographed
    /// first. Also the vocabulary that lets the search parser recognise "fukuoka"
    /// as a place without guessing from the shape of the word.
    var places: [String] { didSet { revision = UUID() } }
    /// Photos keywords on indexed photos, most photos first (iOS 27; empty
    /// below). Add Keyword suggestions, the Keyword rule's field and the
    /// search parser's keyword vocabulary (FS-02.07 §4, §7).
    var keywords: [KeywordCount] { didSet { revision = UUID() } }

    init(
        brands: [String] = [], bodies: [String] = [], lenses: [String] = [], places: [String] = [],
        keywords: [KeywordCount] = []
    ) {
        self.brands = brands
        self.bodies = bodies
        self.lenses = lenses
        self.places = places
        self.keywords = keywords
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
            places: (try? libraryQueries.distinctPlaceTerms()) ?? [],
            keywords: keywordCounts()
        )
        cached = catalog
        return catalog
    }

    /// Recounts only the keywords — after a caption/keyword write, without
    /// the camera, lens and place scans (FS-02.07 §4).
    func refreshKeywords() -> [KeywordCount] {
        var catalog = load()
        catalog.keywords = keywordCounts()
        cached = catalog
        return catalog.keywords
    }

    private func keywordCounts() -> [KeywordCount] {
        guard ExtendedMetadataSupport.isAvailable else { return [] }
        return (try? PhotoKeywordStore(database: libraryQueries.database).keywordCounts()) ?? []
    }
}
