import Foundation

/// Orders matched groups the way Photos' `PSISuggestionRanker` does — how much
/// of the name the typed text covers, the kind of value, how many photos —
/// and caps the list (FS-01.03c §2).
enum SearchSuggestionRanker {
    /// How well a name matches what was typed. Lower is better.
    enum MatchQuality: Int, Comparable {
        /// The whole typed text starts the name: `can` → `Canon EOS R6`.
        case nameStart
        /// Every typed word starts some word of the name, the first one first:
        /// `r6` → `Canon EOS R6`.
        case wordStart

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func quality(of name: String, typed: String) -> MatchQuality {
        let foldedName = SearchFolding.fold(name)
        let foldedTyped = SearchFolding.fold(typed).trimmingCharacters(in: .whitespaces)
        return !foldedTyped.isEmpty && foldedName.hasPrefix(foldedTyped) ? .nameStart : .wordStart
    }

    /// Best first: match quality, then the kind of value, then more photos,
    /// then the name. Groups with no photo left are dropped.
    static func rank(_ groups: [SearchGroup], typed: String, limit: Int) -> [SearchGroup] {
        let scored = groups
            .filter { $0.count > 0 }
            .map { (group: $0, quality: quality(of: $0.name, typed: typed)) }
        let sorted = scored.sorted { a, b in
            if a.quality != b.quality { return a.quality < b.quality }
            if a.group.category != b.group.category { return a.group.category < b.group.category }
            if a.group.count != b.group.count { return a.group.count > b.group.count }
            return a.group.name.localizedStandardCompare(b.group.name) == .orderedAscending
        }
        return Array(sorted.prefix(limit).map(\.group))
    }

    /// The empty field's *In Your Library* rows (FS-01.03c §5): the two
    /// biggest cameras, lenses and places, and the newest year.
    static func libraryHighlights(_ groups: [SearchGroup]) -> [SearchGroup] {
        func top(_ category: SearchGroupCategory, _ n: Int) -> [SearchGroup] {
            groups.filter { $0.category == category && $0.count > 0 }
                .sorted { $0.count > $1.count }
                .prefix(n)
                .map { $0 }
        }
        let newestYear = groups
            .filter { $0.category == .year && $0.count > 0 }
            .max { $0.name < $1.name }
        return top(.camera, 2) + top(.lens, 2) + top(.place, 2) + (newestYear.map { [$0] } ?? [])
    }
}

/// *Did you mean …?* (FS-01.03c §6): the group name nearest to what was typed,
/// asked only when nothing matched. Never applied on its own.
enum SearchSpelling {
    /// Names shorter than this are left alone: `R6` one letter off is `R5`,
    /// a different camera, not a typo.
    static let minimumLength = 5
    static let maximumDistance = 2

    static func suggestion(for typed: String, in groups: [SearchGroup]) -> SearchGroup? {
        let target = Array(SearchFolding.fold(typed).trimmingCharacters(in: .whitespaces))
        guard target.count >= minimumLength else { return nil }
        var best: (group: SearchGroup, distance: Int)?
        for group in groups where group.count > 0 {
            let name = Array(SearchFolding.fold(group.name))
            guard name.count >= minimumLength, abs(name.count - target.count) <= maximumDistance else { continue }
            let distance = damerauLevenshtein(target, name, limit: maximumDistance)
            guard distance <= maximumDistance else { continue }
            if best == nil
                || distance < best!.distance
                || (distance == best!.distance && group.count > best!.group.count) {
                best = (group, distance)
            }
        }
        // Distance 0 would mean it matched — then there was no typo to fix.
        guard let best, best.distance > 0 else { return nil }
        return best.group
    }

    /// Optimal string alignment distance (adjacent swaps count as one edit),
    /// stopping early once every path is past `limit`.
    static func damerauLevenshtein(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }
}
