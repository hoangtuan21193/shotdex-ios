import CoreGraphics
import Foundation

/// The movie page's stand-in for a player (FS-23.08 §4): nothing plays,
/// but the Audio & Subtitles panel works on it as on a playing movie — its
/// audio tracks are read from the file's header or from Plex, and a choice
/// is kept by its place in the file for the real player to match.
@MainActor
final class MovieProbePlayer: MoviePlaying {
    private(set) var state: MoviePlaybackState = .paused
    let timeMs: Int64 = 0
    let durationMs: Int64
    var rate: Double = 1
    private(set) var audioTracks: [MovieAudioTrack] = []
    private(set) var selectedAudioTrackId: String?
    var audioDelayMs = 0
    let videoSize: CGSize = .zero
    var fillsFrame = false
    let canPictureInPicture = false
    let isPictureInPictureActive = false
    private(set) var knowsTracks = false
    var onChange: (() -> Void)?

    init(durationMs: Int64) {
        self.durationMs = durationMs
    }

    /// The file's tracks, once read; nil when they could not be.
    func setAudioTracks(_ tracks: [MovieAudioTrack]?) {
        audioTracks = tracks ?? []
        knowsTracks = tracks != nil
        selectedAudioTrackId = audioTracks.first(where: \.isDefault)?.id ?? audioTracks.first?.id
        onChange?()
    }

    func play() {}
    func pause() {}
    func seek(toMs: Int64) {}
    func togglePictureInPicture() {}
    func showEmbeddedSubtitle(at index: Int?) {}
    func close() {}

    func selectAudioTrack(id: String) {
        selectedAudioTrackId = id
        onChange?()
    }
}
