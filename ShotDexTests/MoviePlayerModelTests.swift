import Foundation
import Testing
@testable import ShotDex

/// A movie engine that only keeps numbers — what the player model asked of
/// it, and what it says back.
@MainActor final class FakeMoviePlayer: MoviePlaying {
    var state: MoviePlaybackState = .opening
    var timeMs: Int64 = 0
    var durationMs: Int64 = 0
    var rate: Double = 1
    var audioTracks: [MovieAudioTrack] = []
    var selectedAudioTrackId: String?
    var audioDelayMs = 0
    var onChange: (() -> Void)?
    private(set) var seeks: [Int64] = []
    private(set) var isClosed = false

    func play() { report { $0.state = .playing } }
    func pause() { report { $0.state = .paused } }
    func seek(toMs ms: Int64) {
        seeks.append(ms)
        report { $0.timeMs = ms }
    }
    func selectAudioTrack(id: String) { report { $0.selectedAudioTrackId = id } }
    func close() { isClosed = true }

    /// Changes something and tells the model, as VLC's delegate does.
    func report(_ change: (FakeMoviePlayer) -> Void) {
        change(self)
        onChange?()
    }
}

/// FS-23.02 §3: transport, gestures and the touch lock.
@Suite @MainActor struct MoviePlayerModelTests {
    private func playing(atMs ms: Int64 = 600_000, durationMs: Int64 = 7_200_000, store: MovieStore? = nil) -> (MoviePlayerModel, FakeMoviePlayer) {
        let engine = FakeMoviePlayer()
        engine.durationMs = durationMs
        let model = MoviePlayerModel(movie: Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1_000, state: .onDevice, addedAt: 0), player: engine, store: store)
        model.start()
        engine.report { $0.timeMs = ms }
        return (model, engine)
    }

    /// AC-16: locked, a double tap on the right half moves nothing and only
    /// the unlock button comes up.
    @Test func touchLockSwallowsDoubleTap() {
        let (model, engine) = playing()
        model.lock()
        model.doubleTap(isLeading: false)
        #expect(engine.seeks.isEmpty)
        #expect(model.timeMs == 600_000)
        #expect(!model.isChromeVisible)
        #expect(model.showsUnlock)

        model.unlock()
        model.doubleTap(isLeading: false)
        #expect(engine.seeks == [610_000])
        #expect(model.isChromeVisible)
    }

    /// Locked, a single tap toggles the unlock button and never the chrome.
    @Test func lockedTapShowsOnlyUnlock() {
        let (model, _) = playing()
        model.lock()
        model.tapPicture()
        #expect(model.showsUnlock)
        #expect(!model.isChromeVisible)
        model.hideAfterIdle()
        #expect(!model.showsUnlock)
        #expect(!model.isChromeVisible)
    }

    /// Double tap halves skip ten seconds and stop at the ends.
    @Test func doubleTapSkipsAndClamps() {
        let (model, engine) = playing(atMs: 4_000, durationMs: 60_000)
        model.doubleTap(isLeading: true)
        #expect(engine.seeks.last == 0)
        engine.report { $0.timeMs = 55_000 }
        model.doubleTap(isLeading: false)
        #expect(engine.seeks.last == 60_000)
    }

    /// One tap toggles the chrome; idle hides it while playing, never while
    /// paused or scrubbing.
    @Test func chromeHidesOnlyWhilePlaying() {
        let (model, _) = playing()
        #expect(model.isChromeVisible)
        model.scrub(toMs: 1_000_000)
        model.hideAfterIdle()
        #expect(model.isChromeVisible)
        #expect(model.displayMs == 1_000_000)
        model.endScrub()
        #expect(model.timeMs == 1_000_000)

        model.togglePlay()
        #expect(model.state == .paused)
        model.hideAfterIdle()
        #expect(model.isChromeVisible)

        model.togglePlay()
        model.hideAfterIdle()
        #expect(!model.isChromeVisible)
        model.tapPicture()
        #expect(model.isChromeVisible)
    }

    /// Speed goes to the engine and is remembered for the movie.
    @Test func speedIsRememberedPerMovie() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MovieStore(database: database, plexTokens: InMemoryPasswordStore())
        let movie = Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1_000, state: .onDevice, addedAt: 0)
        try store.add(movie)
        let engine = FakeMoviePlayer()
        let model = MoviePlayerModel(movie: movie, player: engine, store: store)
        model.setRate(1.5)
        #expect(engine.rate == 1.5)
        let saved = try #require(try store.movies().first)
        #expect(saved.playbackRate == 1.5)

        let reopened = FakeMoviePlayer()
        MoviePlayerModel(movie: saved, player: reopened).start()
        #expect(reopened.rate == 1.5)
    }

    @Test func clockText() {
        #expect(MoviePlayerText.clock(2_832_000, longest: 3_000_000) == "47:12")
        #expect(MoviePlayerText.clock(2_832_000, longest: 9_960_000) == "0:47:12")
        #expect(MoviePlayerText.remaining(2_832_000, of: 9_960_000) == "\u{2212}1:58:48")
        #expect(MoviePlayerText.remaining(0, of: 0) == "")
        #expect(MoviePlayerText.rate(1.25) == "1.25\u{00D7}")
        #expect(MoviePlayerText.rate(1) == "1\u{00D7}")
    }
}
