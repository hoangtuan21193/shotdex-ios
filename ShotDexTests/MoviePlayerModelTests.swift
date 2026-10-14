import Foundation
import SwiftUI
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
    var videoSize: CGSize = .zero
    var fillsFrame = false
    var canPictureInPicture = false
    var isPictureInPictureActive = false
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
    func togglePictureInPicture() { report { $0.isPictureInPictureActive.toggle() } }
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

    /// Fit ↔ Fill reaches the engine; a locked pinch is ignored by the
    /// screen, the button path is the model's.
    @Test func fillTogglesTheEngine() {
        let (model, engine) = playing()
        model.setFill(true)
        #expect(engine.fillsFrame)
        #expect(model.fillsFrame)
        model.setFill(false)
        #expect(!engine.fillsFrame)
    }

    /// Leaving the app pauses, unless picture in picture carries the movie.
    @Test func backgroundPausesUnlessPictureInPicture() {
        let (model, engine) = playing()
        model.enterBackground()
        #expect(engine.state == .paused)

        engine.play()
        engine.togglePictureInPicture()
        model.enterBackground()
        #expect(engine.state == .playing)
    }

    /// FS-23.02 §4: a phone held upright turns the stage for a wide movie;
    /// the iPad, a tall movie and a landscape window do not.
    @Test func phoneTurnsTheStageForWideMovies() {
        let island = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        let phone = MoviePlayerLayout(size: CGSize(width: 402, height: 874), safeArea: island, isCompactWidth: true, isLandscapePicture: true)
        #expect(phone.isRotated)
        #expect(phone.stageSize == CGSize(width: 874, height: 402))
        #expect(phone.chromeInsets.leading == 62)
        #expect(phone.chromeInsets.trailing == 62)

        #expect(!MoviePlayerLayout(size: CGSize(width: 402, height: 874), safeArea: island, isCompactWidth: true, isLandscapePicture: false).isRotated)
        #expect(!MoviePlayerLayout(size: CGSize(width: 1032, height: 1376), safeArea: EdgeInsets(), isCompactWidth: false, isLandscapePicture: true).isRotated)
        #expect(!MoviePlayerLayout(size: CGSize(width: 874, height: 402), safeArea: EdgeInsets(), isCompactWidth: true, isLandscapePicture: true).isRotated)
    }

    private func stored(positionMs: Int64 = 0, durationMs: Int64? = 7_200_000) throws -> (MovieStore, Movie) {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let movie = Movie(sourceId: nil, title: "Dune", originalFileName: "Dune.mkv", byteCount: 1_000, durationMs: durationMs, state: .onDevice, addedAt: 0, positionMs: positionMs)
        try store.add(movie)
        return (store, movie)
    }

    /// AC-14: a 2:00:00 movie left at 47:12 opens there with the label;
    /// Start Over goes to 0:00.
    @Test func resumeAndStartOver() throws {
        let (store, movie) = try stored(positionMs: 2_832_000)
        let engine = FakeMoviePlayer()
        engine.durationMs = 7_200_000
        let model = MoviePlayerModel(movie: movie, player: engine, store: store)
        model.start()
        #expect(engine.seeks == [2_832_000])
        #expect(model.timeMs == 2_832_000)
        #expect(model.resumedAtMs == 2_832_000)

        model.startOver()
        #expect(engine.seeks.last == 0)
        #expect(model.resumedAtMs == nil)
        #expect(try store.movies().first?.positionMs == 0)
    }

    /// Under a minute, or past 95%, the movie starts from the top.
    @Test func resumeOnlyBetweenAMinuteAnd95Percent() {
        #expect(MoviePlaybackPosition.resumeMs(saved: 59_000, durationMs: 7_200_000) == nil)
        #expect(MoviePlaybackPosition.resumeMs(saved: 61_000, durationMs: 7_200_000) == 61_000)
        #expect(MoviePlaybackPosition.resumeMs(saved: 6_840_000, durationMs: 7_200_000) == nil)
        #expect(MoviePlaybackPosition.resumeMs(saved: 6_839_000, durationMs: 7_200_000) == 6_839_000)
        #expect(MoviePlaybackPosition.resumeMs(saved: 600_000, durationMs: 0) == 600_000)
    }

    /// The place is written every 10 s of play, on pause and on close —
    /// and never the 0:00 before the resume seek.
    @Test func positionIsSavedAsItPlays() throws {
        let (store, movie) = try stored(positionMs: 600_000)
        let engine = FakeMoviePlayer()
        engine.durationMs = 7_200_000
        let model = MoviePlayerModel(movie: movie, player: engine, store: store)
        #expect(try store.movies().first?.positionMs == 600_000)
        model.start()
        engine.report { $0.timeMs = 605_000 }
        #expect(try store.movies().first?.positionMs == 600_000)
        engine.report { $0.timeMs = 610_000 }
        #expect(try store.movies().first?.positionMs == 610_000)
        engine.report { $0.timeMs = 612_000 }
        model.togglePlay()
        #expect(try store.movies().first?.positionMs == 612_000)
        engine.report { $0.timeMs = 613_500 }
        model.close()
        #expect(try store.movies().first?.positionMs == 613_500)
        #expect(engine.isClosed)
    }

    /// Closing past 95% marks the movie watched and next time starts at 0.
    @Test func closingInTheCreditsMarksWatched() throws {
        let (store, movie) = try stored(durationMs: nil)
        let engine = FakeMoviePlayer()
        let model = MoviePlayerModel(movie: movie, player: engine, store: store)
        model.start()
        engine.report {
            $0.durationMs = 7_200_000
            $0.timeMs = 6_900_000
        }
        model.close()
        let saved = try #require(try store.movies().first)
        #expect(saved.isWatched)
        #expect(saved.positionMs == 0)
        #expect(saved.durationMs == 7_200_000)
    }
}
