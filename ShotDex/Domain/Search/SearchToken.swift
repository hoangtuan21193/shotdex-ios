import Foundation

/// A chosen suggestion, shown as a token in the search field (FS-01.03c §3) —
/// Photos' `PXSearchToken`. Its rules narrow everything typed after it.
struct SearchToken: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var rules: [SmartAlbumRule]

    init(name: String, symbol: String, rules: [SmartAlbumRule]) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.rules = rules
    }

    init(group: SearchGroup) {
        self.init(name: group.name, symbol: group.category.symbol, rules: [group.rule])
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One row of the suggestion list.
enum SearchSuggestion: Identifiable, Hashable, Sendable {
    /// How the parser reads the typed text, when no single value says it
    /// (`f > 1.2`, `iso over 3200 before 2020`).
    case interpretation(text: String, rules: [SmartAlbumRule])
    /// A value of the library that matches what is typed.
    case group(SearchGroup)
    /// Nothing matched; the nearest name (FS-01.03c §6).
    case didYouMean(SearchGroup)

    var id: String {
        switch self {
        case .interpretation(let text, _): "i:\(text)"
        case .group(let group): "g:\(group.id)"
        case .didYouMean(let group): "d:\(group.id)"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
