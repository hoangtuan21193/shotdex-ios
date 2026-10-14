import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §2: a folder source lists every movie under it by name and
/// size, with the subtitles and poster beside each.
@Suite @MainActor struct MovieLibraryScanTests {
    private func store() throws -> MovieStore {
        MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
    }

    private func source(_ store: MovieStore, folder: String = "Movies") throws -> MovieSource {
        let source = MovieSource(kind: .folder, name: "Movies on NAS Home", folder: folder)
        try store.saveSource(source)
        return source
    }

    private func bytes(_ n: Int) -> Data { Data(repeating: 1, count: n) }

    /// AC-2: three movies, Dune with two subtitles beside it, all Stream.
    @Test func folderSourceListsMovies() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Dune.Part.Two.2024.2160p.x265.mkv", bytes(30))
        nas.put("Movies/Dune.Part.Two.2024.2160p.x265.en.srt", bytes(3))
        nas.put("Movies/Dune.Part.Two.2024.2160p.x265.vi.srt", bytes(3))
        nas.put("Movies/Perfect.Days.2023.1080p.mkv", bytes(20))
        nas.put("Movies/Past.Lives.2023.mp4", bytes(10))
        nas.put("Movies/notes.txt", bytes(1))
        let store = try store()
        let source = try source(store)

        let merge = try await MovieSourceSync.scan(source, client: nas, store: store)

        #expect(merge.added == 3)
        let movies = try store.movies()
        #expect(Set(movies.map { "\($0.displayTitle) · \($0.year ?? 0)" }) == ["Dune Part Two · 2024", "Perfect Days · 2023", "Past Lives · 2023"])
        #expect(movies.allSatisfy { $0.state == .stream && !$0.isOnDevice })
        let dune = try #require(movies.first { $0.title == "Dune Part Two" })
        #expect(dune.byteCount == 30)
        let subtitles = try store.subtitles(movieId: dune.id)
        #expect(Set(subtitles.compactMap(\.language)) == ["en", "vi"])
        #expect(subtitles.allSatisfy { $0.origin == .sidecar && $0.fileName.isEmpty && $0.remotePath != nil })
        #expect(try store.source(id: source.id)?.isReachable == true)
    }

    /// AC-43 (scan half): listing never opens a movie — no range read, no
    /// download — and the poster beside a movie is noted by path.
    @Test func scanNeverOpensFiles() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/A/A.mkv", bytes(30))
        nas.put("Movies/A/poster.jpg", bytes(5))
        nas.put("Movies/B.mp4", bytes(30))
        nas.put("Movies/C.mkv", bytes(30))
        let store = try store()

        try await MovieSourceSync.scan(try source(store), client: nas, store: store)

        #expect(nas.rangeReadPaths.isEmpty)
        #expect(nas.downloadCount == 0)
        let movies = try store.movies()
        #expect(movies.first { $0.originalFileName == "A.mkv" }?.posterPath == "Movies/A/poster.jpg")
        #expect(movies.first { $0.originalFileName == "C.mkv" }?.posterPath == nil)
    }

    @Test func subfoldersAndHousekeeping() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Sci-Fi/Arrival.2016.mkv", bytes(1))
        nas.put("Movies/Shows/Severance/Season 2/Severance.S02E04.mkv", bytes(1))
        nas.put("Movies/@eaDir/Arrival.2016.mkv/SYNOVIDEO_VIDEO_SCREENSHOT.jpg", bytes(1))
        nas.put("Movies/@eaDir/junk.mkv", bytes(1))
        nas.put("Movies/.hidden/secret.mkv", bytes(1))
        let store = try store()

        try await MovieSourceSync.scan(try source(store), client: nas, store: store)

        let movies = try store.movies()
        #expect(Set(movies.map(\.originalFileName)) == ["Arrival.2016.mkv", "Severance.S02E04.mkv"])
        let episode = try #require(movies.first { $0.season == 2 })
        #expect(episode.episode == 4)
        #expect(episode.remotePath == "Movies/Shows/Severance/Season 2/Severance.S02E04.mkv")
    }

    /// FS-23.01 §3: a source that does not answer is marked out of reach and
    /// keeps every movie it had.
    @Test func unreachableKeepsEverything() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Heat.1995.mkv", bytes(1))
        let store = try store()
        let source = try source(store)
        try await MovieSourceSync.scan(source, client: nas, store: store)

        nas.entriesError = .unreachable(host: "nas.local")
        try await MovieSourceSync.scan(source, client: nas, store: store)
        #expect(try store.source(id: source.id)?.isReachable == false)
        #expect(try store.movies().count == 1)

        nas.entriesError = nil
        nas.connectError = .unreachable(host: "nas.local")
        try await MovieSourceSync.scan(source, client: nas, store: store)
        #expect(try store.movies().count == 1)
    }

    /// One subfolder timing out hides nothing that lived in it.
    @Test func failedSubfolderHidesNothing() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Old/Heat.1995.mkv", bytes(1))
        nas.put("Movies/Dune.mkv", bytes(1))
        let store = try store()
        let source = try source(store)
        try await MovieSourceSync.scan(source, client: nas, store: store)

        nas.entriesErrorPaths["Movies/Old"] = .connectionLost
        let merge = try await MovieSourceSync.scan(source, client: nas, store: store)
        #expect(merge.markedRemoved == 0)
        #expect(try store.movies().count == 2)
    }

    /// A subtitle removed on the NAS leaves the movie's list; one the user
    /// imported stays.
    @Test func sidecarsFollowTheFolder() async throws {
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Heat.mkv", bytes(1))
        nas.put("Movies/Heat.en.srt", bytes(1))
        let store = try store()
        let source = try source(store)
        try await MovieSourceSync.scan(source, client: nas, store: store)
        let heat = try #require(try store.movies().first)
        try store.saveSubtitle(MovieSubtitle(movieId: heat.id, language: "vi", origin: .imported, format: .srt, fileName: "vi.srt"))

        try await nas.remove("Movies/Heat.en.srt")
        try await MovieSourceSync.scan(source, client: nas, store: store)

        #expect(try store.subtitles(movieId: heat.id).map(\.origin) == [.imported])
    }

    @Test func subtitleNamesBesideAMovie() {
        let found = MovieFolderScanner.subtitles(
            for: "Dune.mkv", in: "M",
            siblings: ["Dune.mkv", "Dune.srt", "Dune.English.forced.srt", "dune.vie.ass", "Dune 2.srt", "Heat.en.srt", "Dune_ja.vtt"]
        )
        #expect(found.map(\.remotePath) == ["M/Dune.English.forced.srt", "M/Dune.srt", "M/Dune_ja.vtt", "M/dune.vie.ass"])
        #expect(found.map(\.language) == ["en", nil, "ja", "vi"])
        #expect(found.map(\.format) == [.srt, .srt, .vtt, .ass])
    }
}
