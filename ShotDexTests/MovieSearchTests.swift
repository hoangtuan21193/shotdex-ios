import Foundation
import Testing
@testable import ShotDex

private func movie(
    _ title: String, year: Int? = nil, file: String? = nil, added: Int = 0, played: Int? = nil,
    state: Movie.State = .stream, watched: Bool = false, season: Int? = nil, episode: Int? = nil
) -> Movie {
    Movie(
        id: title + (season.map { "-\($0)-\(episode ?? 0)" } ?? ""), sourceId: "s", title: title, year: year,
        season: season, episode: episode, originalFileName: file ?? "\(title).mkv", byteCount: 1, state: state,
        addedAt: added, lastPlayedAt: played, isWatched: watched
    )
}

/// FS-23.01 §4: Search runs over title, year and file name, offline.
@Suite struct MovieSearchTests {
    /// AC-44: 128 movies; `dune 2024` finds one, `x265` finds by file name.
    @Test func titleYearFileName() {
        var library = (0..<125).map { movie("Film \($0)", year: 1990 + $0 % 30) }
        library.append(movie("Dune Part Two", year: 2024, file: "Dune.Part.Two.2024.2160p.x265.mkv"))
        library.append(movie("Dune", year: 2021, file: "Dune.2021.1080p.mkv"))
        library.append(movie("Dune", year: 1984, file: "Dune.1984.mkv"))
        #expect(library.count == 128)

        var query = MovieLibraryQuery(text: "dune 2024")
        #expect(query.apply(library).map(\.title) == ["Dune Part Two"])
        query.text = "x265"
        #expect(query.apply(library).map(\.title) == ["Dune Part Two"])
        query.text = "  DUNE "
        #expect(query.apply(library).count == 3)
    }

    @Test func foldsAccentsAndRename() {
        var renamed = movie("Do Thi Ru Ngu", year: 2019)
        renamed.customTitle = "Đô Thị Ru Ngủ"
        let library = [renamed, movie("Amélie", year: 2001), movie("Severance", file: "Severance.S02E04.mkv", season: 2, episode: 4)]
        #expect(MovieLibraryQuery(text: "do thi").apply(library).count == 1)
        #expect(MovieLibraryQuery(text: "ĐÔ").apply(library).count == 1)
        #expect(MovieLibraryQuery(text: "amelie").apply(library).map(\.title) == ["Amélie"])
        #expect(MovieLibraryQuery(text: "s02e04").apply(library).map(\.title) == ["Severance"])
    }

    @Test func filtersAndHidden() {
        var hidden = movie("Gone", year: 2000)
        hidden.removedFromSourceAt = 5
        var orphanDownload = movie("Kept", state: .onDevice)
        orphanDownload.removedFromSourceAt = 5
        let library = [movie("A", state: .onDevice), movie("B", watched: true), movie("C", state: .downloading), hidden, orphanDownload]

        #expect(Set(MovieLibraryQuery().apply(library).map(\.title)) == ["A", "B", "C", "Kept"])
        #expect(Set(MovieLibraryQuery(filter: .onDevice).apply(library).map(\.title)) == ["A", "Kept"])
        #expect(Set(MovieLibraryQuery(filter: .unwatched).apply(library).map(\.title)) == ["A", "C", "Kept"])
        #expect(MovieLibraryQuery.counts(library) == (4, 2))
    }
}

/// FS-23.01 §4 ⋯ › Sort.
@Suite struct MovieSortTests {
    /// AC-45: five movies, every order; Recently Added is the default.
    @Test func allOrders() {
        let library = [
            movie("Heat", year: 1995, added: 10, played: 300),
            movie("arrival", year: 2016, added: 50),
            movie("Dune", year: 2021, added: 30, played: 900),
            movie("Alien", year: 1979, added: 20, played: 100),
            movie("Brazil", added: 40),
        ]
        #expect(MovieLibraryQuery().sort == .recentlyAdded)
        #expect(MovieLibraryQuery().apply(library).map(\.title) == ["arrival", "Brazil", "Dune", "Alien", "Heat"])
        #expect(MovieLibraryQuery(sort: .title).apply(library).map(\.title) == ["Alien", "arrival", "Brazil", "Dune", "Heat"])
        #expect(MovieLibraryQuery(sort: .year).apply(library).map(\.title) == ["Dune", "arrival", "Heat", "Alien", "Brazil"])
        #expect(MovieLibraryQuery(sort: .recentlyWatched).apply(library).map(\.title) == ["Dune", "Heat", "Alien", "arrival", "Brazil"])
    }

    @Test func titleSortsEpisodesInOrder() {
        let library = [
            movie("Severance", season: 2, episode: 1), movie("Severance", season: 1, episode: 9),
            movie("Severance", season: 1, episode: 10), movie("Film 10"), movie("Film 9"),
        ]
        let sorted = MovieLibraryQuery(sort: .title).apply(library)
        #expect(sorted.map(\.title) == ["Film 9", "Film 10", "Severance", "Severance", "Severance"])
        #expect(sorted.suffix(3).map { "\($0.season!)x\($0.episode!)" } == ["1x9", "1x10", "2x1"])
    }
}
