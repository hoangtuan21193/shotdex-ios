import Foundation

/// What the Movies screen shows: search text, the filter row and the sort
/// (FS-23.01 §4). Pure — runs over the rows already in memory, so it works
/// in airplane mode.
struct MovieLibraryQuery: Equatable, Sendable {
    enum Filter: String, CaseIterable, Sendable {
        case all
        /// Plays with no network.
        case onDevice
        case unwatched
    }

    enum Sort: String, CaseIterable, Sendable {
        case recentlyAdded
        case title
        case year
        case recentlyWatched
    }

    var text = ""
    var filter: Filter = .all
    var sort: Sort = .recentlyAdded

    func apply(_ movies: [Movie]) -> [Movie] {
        let tokens = Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = movies.filter { movie in
            guard !movie.isHidden else { return false }
            switch filter {
            case .all: break
            case .onDevice: guard movie.isOnDevice else { return false }
            case .unwatched: guard !movie.isWatched else { return false }
            }
            guard !tokens.isEmpty else { return true }
            let haystack = Self.haystack(movie)
            return tokens.allSatisfy { haystack.contains($0) }
        }
        return kept.sorted(by: sort.areInIncreasingOrder)
    }

    /// `128 movies · 3 on this iPhone` — counted over the whole library,
    /// not the search.
    static func counts(_ movies: [Movie]) -> (total: Int, onDevice: Int) {
        let shown = movies.filter { !$0.isHidden }
        return (shown.count, shown.filter(\.isOnDevice).count)
    }

    /// Title, the source's title, year, episode and file name, folded.
    private static func haystack(_ movie: Movie) -> String {
        var parts = [movie.displayTitle, movie.title, movie.originalFileName]
        if let year = movie.year { parts.append(String(year)) }
        if let season = movie.season, let episode = movie.episode {
            parts.append(String(format: "s%02de%02d", season, episode))
        }
        return fold(parts.joined(separator: " "))
    }

    /// Case and accents off, `đ` as `d`, so `phim` finds `Phím` and `do` finds `Đỏ`.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }
}

extension MovieLibraryQuery.Sort {
    func areInIncreasingOrder(_ a: Movie, _ b: Movie) -> Bool {
        switch self {
        case .recentlyAdded:
            if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
        case .title:
            break
        case .year:
            // Newest first; no year last.
            switch (a.year, b.year) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        case .recentlyWatched:
            // Last played first; never played after, newest added first.
            switch (a.lastPlayedAt, b.lastPlayedAt) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil) where a.addedAt != b.addedAt: return a.addedAt > b.addedAt
            default: break
            }
        }
        return Self.byTitle(a, b)
    }

    /// Title as people read it, then season and episode.
    static func byTitle(_ a: Movie, _ b: Movie) -> Bool {
        let order = a.displayTitle.localizedStandardCompare(b.displayTitle)
        if order != .orderedSame { return order == .orderedAscending }
        if (a.season ?? 0) != (b.season ?? 0) { return (a.season ?? 0) < (b.season ?? 0) }
        if (a.episode ?? 0) != (b.episode ?? 0) { return (a.episode ?? 0) < (b.episode ?? 0) }
        return a.id < b.id
    }
}
