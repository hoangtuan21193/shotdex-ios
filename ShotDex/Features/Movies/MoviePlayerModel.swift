import CoreGraphics
import Foundation
import Observation

/// One playback (FS-23.02): mirrors the engine's state for the screen and
/// owns the transport — chrome, touch lock, skips, speed (§3).
@MainActor
@Observable
final class MoviePlayerModel {
    static let skipMs: Int64 = 10_000
    static let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    let movie: Movie
    let player: any MoviePlaying

    private(set) var state: MoviePlaybackState = .opening
    private(set) var timeMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var audioTracks: [MovieAudioTrack] = []
    private(set) var selectedAudioTrackId: String?
    private(set) var rate: Double
    private(set) var videoSize: CGSize = .zero
    private(set) var fillsFrame = false
    private(set) var canPictureInPicture = false
    private(set) var isPictureInPictureActive = false

    private(set) var isChromeVisible = true
    /// Touch lock (§3): taps only bring up the unlock button.
    private(set) var isLocked = false
    private(set) var showsUnlock = false
    /// Bumped on every touch; the screen restarts its 3 s hide timer on it.
    private(set) var interaction = 0
    /// Scrubber held: the chrome stays up and the label follows the finger.
    private(set) var scrubMs: Int64?
    /// `Resumed at 47:12 · Start Over`, for 5 s after opening (§2).
    private(set) var resumedAtMs: Int64?
    /// Where to go once the engine plays — VLC drops a seek made earlier.
    private var pendingResumeMs: Int64?
    private var lastSavedMs: Int64 = 0
    private var hasMarkedWatched = false
    private var hasStoredDuration = false
    /// When the movie time last moved — buffering reports alone do not
    /// mean the picture stopped.
    private var lastProgress = Date()

    /// Lets go of the stream's connection (FS-23.01 §3).
    private let onClose: () -> Void
    private let store: MovieStore?

    init(movie: Movie, player: any MoviePlaying, store: MovieStore? = nil, onClose: @escaping () -> Void = {}) {
        self.movie = movie
        self.player = player
        self.store = store
        self.onClose = onClose
        durationMs = movie.durationMs ?? 0
        rate = Self.rates.contains(movie.playbackRate) ? movie.playbackRate : 1
        pendingResumeMs = MoviePlaybackPosition.resumeMs(saved: movie.positionMs, durationMs: movie.durationMs ?? 0)
        player.onChange = { [weak self] in self?.sync() }
        sync()
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var failureReason: String? {
        if case .failed(let reason) = state { return reason }
        return nil
    }

    var isPlaying: Bool { state == .playing || state == .buffering }

    /// What the elapsed label and the scrubber show.
    var displayMs: Int64 { scrubMs ?? timeMs }

    /// The picture is wider than tall — or not decoded yet, where a movie
    /// almost always is (§4: the phone turns the frame for it).
    var isLandscapePicture: Bool {
        videoSize.width <= 0 || videoSize.width >= videoSize.height
    }

    func start() {
        VideoAudioSession.activate()
        if rate != 1 { player.rate = rate }
        player.play()
    }

    /// Spinner: opening, or playing with the clock stuck for over a second
    /// (FS-23.02 §2 — never over a picture that moves).
    func needsSpinner(at now: Date = Date()) -> Bool {
        switch state {
        case .opening: true
        case .buffering, .playing: now.timeIntervalSince(lastProgress) > 1
        default: false
        }
    }

    func togglePlay() {
        touched()
        if isPlaying {
            player.pause()
            savePosition()
        } else {
            player.play()
        }
    }

    /// From the top, from the resume label.
    func startOver() {
        resumedAtMs = nil
        seek(toMs: 0)
        savePosition()
    }

    func dismissResumeNotice() {
        resumedAtMs = nil
    }

    // MARK: Gestures (§3)

    /// One tap on the picture: chrome on/off, or — locked — the unlock
    /// button and nothing else.
    func tapPicture() {
        if isLocked {
            showsUnlock.toggle()
        } else {
            isChromeVisible.toggle()
        }
        interaction += 1
    }

    /// Double tap: −10 s on the leading half, +10 s on the trailing half.
    /// Locked, it is only a tap — a knee on the tray must not move the movie.
    func doubleTap(isLeading: Bool) {
        guard !isLocked else {
            showsUnlock = true
            interaction += 1
            return
        }
        skip(by: isLeading ? -Self.skipMs : Self.skipMs)
    }

    func skip(by deltaMs: Int64) {
        seek(toMs: timeMs + deltaMs)
    }

    func seek(toMs ms: Int64) {
        touched()
        let upper = durationMs > 0 ? durationMs : Int64.max
        let target = min(max(0, ms), upper)
        player.seek(toMs: target)
        timeMs = target
        lastProgress = Date()
    }

    func scrub(toMs ms: Int64) {
        scrubMs = ms
        interaction += 1
    }

    func endScrub() {
        guard let target = scrubMs else { return }
        scrubMs = nil
        seek(toMs: target)
    }

    func lock() {
        isLocked = true
        isChromeVisible = false
        showsUnlock = false
        interaction += 1
    }

    func unlock() {
        isLocked = false
        showsUnlock = false
        isChromeVisible = true
        interaction += 1
    }

    /// The 3 s timer ran out with no touch: the unlock button goes, and the
    /// chrome too while the movie plays (a paused movie keeps its controls).
    func hideAfterIdle() {
        showsUnlock = false
        guard isPlaying, scrubMs == nil else { return }
        isChromeVisible = false
    }

    /// Fit ↔ Fill (§3): the button, and a pinch out or in.
    func setFill(_ fills: Bool) {
        touched()
        guard fills != fillsFrame else { return }
        player.fillsFrame = fills
        fillsFrame = fills
    }

    func togglePictureInPicture() {
        touched()
        player.togglePictureInPicture()
    }

    /// Leaving the app (§4): the movie carries on only in picture in
    /// picture; there is no background audio.
    func enterBackground() {
        savePosition()
        guard !isPictureInPictureActive, isPlaying else { return }
        player.pause()
    }

    /// Speed, remembered per movie (§3).
    func setRate(_ newRate: Double) {
        touched()
        rate = newRate
        player.rate = newRate
        try? store?.setPlaybackRate(newRate, id: movie.id)
    }

    private func touched() {
        if !isLocked { isChromeVisible = true }
        interaction += 1
    }

    func close() {
        savePosition()
        player.close()
        VideoAudioSession.deactivate()
        onClose()
    }

    private func sync() {
        state = player.state
        if player.timeMs != timeMs { lastProgress = Date() }
        timeMs = player.timeMs
        if player.durationMs > 0 { durationMs = player.durationMs }
        audioTracks = player.audioTracks
        if player.videoSize != videoSize { videoSize = player.videoSize }
        fillsFrame = player.fillsFrame
        canPictureInPicture = player.canPictureInPicture
        isPictureInPictureActive = player.isPictureInPictureActive
        selectedAudioTrackId = player.selectedAudioTrackId
        followPlayback()
    }

    // MARK: Position (§2)

    private func followPlayback() {
        if state == .playing, let target = pendingResumeMs {
            pendingResumeMs = nil
            if MoviePlaybackPosition.resumeMs(saved: target, durationMs: durationMs) != nil {
                player.seek(toMs: target)
                timeMs = target
                lastSavedMs = target
                resumedAtMs = target
            }
        }
        if durationMs > 0, durationMs != (movie.durationMs ?? 0), !hasStoredDuration {
            hasStoredDuration = true
            try? store?.setDuration(durationMs, id: movie.id)
        }
        if state == .ended {
            markWatched()
        } else if isPlaying, abs(timeMs - lastSavedMs) >= MoviePlaybackPosition.saveIntervalMs {
            savePosition()
        }
    }

    /// Every 10 s while playing, on pause, on close and when leaving the
    /// app. From 95% on the movie is watched and starts from the top next
    /// time.
    private func savePosition() {
        guard pendingResumeMs == nil, !hasMarkedWatched else { return }
        if MoviePlaybackPosition.isWatched(positionMs: timeMs, durationMs: durationMs) {
            markWatched()
            return
        }
        lastSavedMs = timeMs
        try? store?.recordPosition(id: movie.id, positionMs: timeMs)
    }

    private func markWatched() {
        guard !hasMarkedWatched else { return }
        hasMarkedWatched = true
        try? store?.setWatched(true, ids: [movie.id])
    }
}
