import Foundation
import Observation

/// One playback (FS-23.02): mirrors the engine's state for the screen.
@MainActor
@Observable
final class MoviePlayerModel {
    let movie: Movie
    let player: any MoviePlaying

    private(set) var state: MoviePlaybackState = .opening
    private(set) var timeMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var audioTracks: [MovieAudioTrack] = []
    private(set) var selectedAudioTrackId: String?
    /// When the movie time last moved — buffering reports alone do not
    /// mean the picture stopped.
    private var lastProgress = Date()

    init(movie: Movie, player: any MoviePlaying) {
        self.movie = movie
        self.player = player
        durationMs = movie.durationMs ?? 0
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

    func start() { player.play() }

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
        if state == .playing || state == .buffering { player.pause() } else { player.play() }
    }

    func close() { player.close() }

    private func sync() {
        state = player.state
        if player.timeMs != timeMs { lastProgress = Date() }
        timeMs = player.timeMs
        if player.durationMs > 0 { durationMs = player.durationMs }
        audioTracks = player.audioTracks
        selectedAudioTrackId = player.selectedAudioTrackId
    }
}
