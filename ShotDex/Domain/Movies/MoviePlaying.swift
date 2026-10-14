import Foundation

/// What the player screen needs from a movie engine (FS-23.02 §1). VLCKit
/// sits behind it in the Data layer, so it can be swapped — an alpha today
/// — and the screen and its model can be tested with a fake.
enum MoviePlaybackState: Equatable, Sendable {
    case opening
    case playing
    case paused
    /// Waiting for bytes; the clock stands still.
    case buffering
    case ended
    /// `Can't Play This Movie` + this one-line reason (FS-23.02 §2).
    case failed(String)
}

@MainActor
protocol MoviePlaying: AnyObject {
    var state: MoviePlaybackState { get }
    /// Last time the engine reported, in movie milliseconds.
    var timeMs: Int64 { get }
    var durationMs: Int64 { get }
    var rate: Double { get set }
    var audioTracks: [MovieAudioTrack] { get }
    var selectedAudioTrackId: String? { get }
    /// Audio Sync (FS-23.02 §3b), milliseconds; positive = audio later.
    var audioDelayMs: Int { get set }
    /// Picture size in pixels; zero until the first frame is decoded.
    var videoSize: CGSize { get }
    /// Fill (§3): crop the edges to fill the frame instead of fitting the
    /// whole picture with black bars.
    var fillsFrame: Bool { get set }
    /// The engine's picture-in-picture window is ready to start.
    var canPictureInPicture: Bool { get }
    var isPictureInPictureActive: Bool { get }
    /// Anything above changed.
    var onChange: (() -> Void)? { get set }

    func play()
    func pause()
    func seek(toMs: Int64)
    func selectAudioTrack(id: String)
    func togglePictureInPicture()
    /// Lets the engine draw one of the file's own subtitle tracks — by its
    /// place among them — for the ones ShotDex cannot read (picture
    /// subtitles; a streamed track without Cues, AC-55). nil: none; ShotDex
    /// draws subtitles itself.
    func showEmbeddedSubtitle(at index: Int?)
    /// Stops and lets go of the file or stream.
    func close()
}
