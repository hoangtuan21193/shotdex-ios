import Foundation
import Testing
@testable import ShotDex

/// FS-23.03 §2–4: the chosen subtitles reach the player, on its clock, in
/// the movie frame.
@Suite @MainActor struct MovieSubtitleOverlayTests {
    private struct Fixture {
        let store: MovieStore
        let files: MovieFileStore
        let movie: Movie
        let english: MovieSubtitle
        let vietnamese: MovieSubtitle
    }

    private let srtEN = "1\n00:01:05,000 --> 00:01:08,000\nWe have to go now.\n\n2\n00:01:10,000 --> 00:01:12,000\n<i>Before the storm.</i>\n"
    private let srtVI = "1\n00:01:05,000 --> 00:01:08,000\nChúng ta phải đi ngay.\n"

    private func fixture(offsetMs: Int = 0) throws -> Fixture {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "subs-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1_000, durationMs: 7_200_000, state: .onDevice, addedAt: 0)
        try store.add(movie)
        var english = MovieSubtitle(movieId: movie.id, language: "en", origin: .sidecar, format: .srt, fileName: "")
        english.fileName = try files.write(Data(srtEN.utf8), named: "en.srt", for: movie.id)
        english.offsetMs = offsetMs
        var vietnamese = MovieSubtitle(movieId: movie.id, language: "vi", origin: .imported, format: .srt, fileName: "")
        vietnamese.fileName = try files.write(Data(srtVI.utf8), named: "vi.srt", for: movie.id)
        try store.saveSubtitle(english)
        try store.saveSubtitle(vietnamese)
        return Fixture(store: store, files: files, movie: movie, english: english, vietnamese: vietnamese)
    }

    private func model(_ f: Fixture, languages: [String] = ["en"]) -> MoviePlayerModel {
        MoviePlayerModel(
            movie: f.movie, player: FakeMoviePlayer(), store: f.store,
            subtitleLanguages: languages, subtitleLoader: MovieSubtitleLoader(files: f.files)
        )
    }

    /// A first open starts with the first Subtitle Language the movie has,
    /// and remembers it.
    @Test func firstOpenPicksSubtitleLanguage() async throws {
        let f = try fixture()
        let player = model(f, languages: ["vi", "en"])
        await player.loadSubtitles()
        #expect(player.subtitleChoice.primaryId == f.vietnamese.id)
        #expect(try f.store.subtitleChoice(movieId: f.movie.id)?.primaryId == f.vietnamese.id)
        #expect(player.primaryTimeline?.cues(atMs: 66_000).first?.plainText == "Chúng ta phải đi ngay.")

        let none = try fixture()
        let silent = model(none, languages: [])
        await silent.loadSubtitles()
        #expect(silent.primaryTimeline == nil)
    }

    /// AC-20 (player): Sync +2.0 s puts the 1:05.000 cue on at 1:07.0.
    @Test func syncDelaysTheCue() async throws {
        let f = try fixture(offsetMs: 2_000)
        try f.store.saveSubtitleChoice(MovieSubtitleChoice(movieId: f.movie.id, primaryId: f.english.id, secondaryId: f.vietnamese.id))
        let player = model(f)
        await player.loadSubtitles()
        let primary = try #require(player.primaryTimeline)
        #expect(primary.cues(atMs: 66_900).isEmpty)
        #expect(primary.cues(atMs: 67_000).first?.plainText == "We have to go now.")
        #expect(player.secondaryTimeline?.cues(atMs: 65_000).first?.plainText == "Chúng ta phải đi ngay.")
    }

    /// The subtitle clock follows the engine's reports and seeks.
    @Test func subtitleClockFollowsThePlayer() {
        let engine = FakeMoviePlayer()
        let player = MoviePlayerModel(movie: Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1, state: .onDevice, addedAt: 0), player: engine)
        player.start()
        engine.report { $0.timeMs = 65_000 }
        let now = MoviePlayerModel.hostTime
        #expect(abs(player.subtitleTimeMs(at: now) - 65_000) < 50)
        #expect(player.subtitleTimeMs(at: now + 0.5) >= 65_450)
        player.seek(toMs: 10_000)
        #expect(abs(player.subtitleTimeMs(at: MoviePlayerModel.hostTime) - 10_000) < 50)
    }

    /// Fit leaves bars; Fill overflows the stage (§4: subtitles go in the
    /// visible part).
    @Test func movieFrameFitsOrFills() {
        let stage = CGRect(x: 0, y: 0, width: 874, height: 402)
        let fit = MovieSubtitleOverlay.movieFrame(videoSize: CGSize(width: 1920, height: 1080), in: stage, fills: false)
        #expect(abs(fit.width - 714.7) < 0.5)
        #expect(fit.height == 402)
        let fill = MovieSubtitleOverlay.movieFrame(videoSize: CGSize(width: 1920, height: 800), in: stage, fills: true)
        #expect(abs(fill.height - 402) < 0.01)
        #expect(fill.width > 874)
        #expect(MovieSubtitleOverlay.movieFrame(videoSize: .zero, in: stage, fills: false) == stage)
    }

    /// Style JSON is read leniently: unknown or broken fields keep their
    /// defaults, sizes stay within 50–200 %.
    @Test func styleDecodesLeniently() {
        #expect(MovieSubtitleStyle.decode("{}") == MovieSubtitleStyle())
        #expect(MovieSubtitleStyle.decode("not json") == MovieSubtitleStyle())
        let style = MovieSubtitleStyle.decode(#"{"position":"primaryBottomSecondaryTop","primary":{"scale":9,"color":"cyan"},"secondary":{"scale":"x"}}"#)
        #expect(style.position == .primaryBottomSecondaryTop)
        #expect(style.primary == MovieSubtitleStyle.Line(scale: 2, color: .cyan))
        #expect(style.secondary == MovieSubtitleStyle().secondary)
        #expect(MovieSubtitleStyle.decode(style.json) == style)
    }
}
