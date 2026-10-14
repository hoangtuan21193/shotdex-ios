import Foundation
import Testing
@testable import ShotDex

/// FS-23.08 — the movie page: audio tracks known before playing, a choice
/// kept by its place in the file, Plex's versions and background, and what
/// the page says.
@Suite @MainActor struct MovieDetailTests {
    private static let twoAudio = MoviePlayerFormatsTests.folder.appending(path: "two-audio.mkv")

    /// AC-63 (header): a Matroska file's audio tracks, in file order, from
    /// its header alone — language, codec and channels for the rows.
    @Test func matroskaAudioTracksFromTheHeader() async throws {
        let source = try FileByteSource(url: Self.twoAudio)
        let tracks = try #require(await MovieTrackProbe.audioTracks(fileName: "two-audio.mkv", source: source, localURL: nil))
        #expect(tracks.map(\.id) == ["file:0", "file:1"])
        #expect(tracks.map { MovieLanguage.code($0.language) } == ["en", "vi"])
        #expect(tracks.map { MovieAudioTrackLabel.detail($0) } == ["AC3 5.1", "AAC Stereo"])
        #expect(source.size > 0)
    }

    /// AC-63 (choice): picked on the page as the third track, the player
    /// opens on its third track, whatever the engine calls it.
    @Test func choiceByPlaceMatchesTheEngine() {
        let engine = [
            MovieAudioTrack(id: "audio/1", language: "eng", isDefault: true),
            MovieAudioTrack(id: "audio/2", language: "ger", isDefault: false),
            MovieAudioTrack(id: "audio/3", language: "jpn", isDefault: false),
        ]
        #expect(MovieTrackChoice.audioTrack(engine, preferredLanguages: ["en"], remembered: "file:2")?.id == "audio/3")
        #expect(MovieTrackChoice.audioTrack(engine, preferredLanguages: ["en"], remembered: "file:9")?.id == "audio/1")
        #expect(MovieAudioTrack.fileIndex("audio/3") == nil)
    }

    /// The page's stand-in: tracks set and chosen without playing; a
    /// choice saved by the panel is the file's place.
    @Test func probeChoiceIsSavedByPlace() throws {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let movie = Movie(sourceId: nil, title: "Film", originalFileName: "Film.mkv", byteCount: 1, state: .stream)
        try store.add(movie)
        let probe = MovieProbePlayer(durationMs: 0)
        let model = MoviePlayerModel(movie: movie, player: probe, store: store)
        #expect(!probe.knowsTracks)
        probe.setAudioTracks([
            MovieAudioTrack(id: "file:0", language: "eng", isDefault: true),
            MovieAudioTrack(id: "file:1", language: "vie", isDefault: false),
        ])
        #expect(model.audioTracks.count == 2)
        model.selectAudio(id: "file:1")
        #expect(try store.movie(id: movie.id)?.audioTrackId == "file:1")
    }

    /// AC-65 (parse): each Plex version carries its own audio streams, and
    /// the item its background.
    @Test func plexVersionAudioAndArt() throws {
        var json = PlexTests.dune(withStreams: false)
        json["art"] = "/library/metadata/101/art/1"
        var media = json["Media"] as! [[String: Any]]
        var parts = media[0]["Part"] as! [[String: Any]]
        parts[0]["Stream"] = [
            ["streamType": 2, "languageCode": "eng", "codec": "truehd", "channels": 8, "default": true],
            ["streamType": 2, "languageCode": "jpn", "codec": "ac3", "channels": 6],
            ["streamType": 3, "key": "/library/streams/77", "languageCode": "vie", "codec": "srt"],
        ]
        media[0]["Part"] = parts
        json["Media"] = media
        let item = try #require(PlexClient.item(json))
        #expect(item.art == "/library/metadata/101/art/1")
        let hd = try #require(item.versions.first { $0.partKey == "/library/parts/hd/file.mkv" })
        #expect(hd.audioTracks.map(\.id) == ["file:0", "file:1"])
        #expect(hd.audioTracks.map { MovieAudioTrackLabel.detail($0) } == ["TrueHD 7.1", "AC3 5.1"])
        #expect(PlexLibrarySync.scanned(item)?.artPath?.contains("art%2F1") == true || PlexLibrarySync.scanned(item)?.artPath?.contains("art/1") == true)
    }

    /// AC-65 (keep): a version chosen on the page keeps its size through
    /// the next library refresh — the download checks against it.
    @Test func chosenVersionSurvivesRefresh() throws {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let source = MovieSource(kind: .plex, name: "Mac Studio", folder: "")
        try store.saveSource(source)
        let item = try #require(PlexClient.item(PlexTests.dune(withStreams: false)))
        let scanned = try #require(PlexLibrarySync.scanned(item))
        _ = try store.mergeScan(sourceId: source.id, found: [scanned], isComplete: true)
        let movie = try #require(try store.movies().first)
        let hd = try #require(item.versions.last)
        try PlexDownloadPreparer(store: store).choose(hd, for: movie)

        _ = try store.mergeScan(sourceId: source.id, found: [scanned], isComplete: true)

        let after = try #require(try store.movie(id: movie.id))
        #expect(after.plexPartKey == hd.partKey)
        #expect(after.byteCount == hd.size)
    }

    /// AC-59, AC-61 (words): what the page says for a movie watched part
    /// way, and for one never opened offline.
    @Test func pageWords() async throws {
        let dependencies = AppDependencies.preview()
        var movie = Movie(sourceId: nil, title: "Dune: Part Two", year: 2024, originalFileName: "Dune.mkv", byteCount: 6_100_000_000,
                          durationMs: 9_960_000, state: .stream)
        movie.positionMs = 2_832_000
        try dependencies.movies.add(movie)
        let model = MovieDetailModel(movie: movie, playback: MoviePlayback(dependencies: dependencies))
        #expect(model.resumeMs == 2_832_000)
        #expect(model.facts == "2024 · 2:46:00")
        await model.load()
        #expect(model.tracks != nil)
        #expect(model.audioSummary == "Chosen when playing")
        #expect(model.subtitleSummary == "Off")

        var fresh = movie
        fresh.positionMs = 0
        #expect(MovieDetailModel(movie: fresh, playback: MoviePlayback(dependencies: dependencies)).resumeMs == nil)
    }
}
