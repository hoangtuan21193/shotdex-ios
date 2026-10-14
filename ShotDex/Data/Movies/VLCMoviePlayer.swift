import Foundation
import os
import UIKit
import VLCKit

/// `MoviePlaying` over VLCKit 4 (FS-23.02 §1). Draws into `view`; subtitles
/// are not VLC's to draw (FS-23.03 §4) — ShotDex's own layer sits on top.
@MainActor
final class VLCMoviePlayer: NSObject, MoviePlaying {
    enum Input {
        case file(URL)
        /// Bytes from a source, read on demand (S1: no VLC URL ever sees a
        /// password or token).
        case stream(InputStream, fileName: String)
    }

    let view: UIView
    private let drawable: MovieDrawableView
    private let player: VLCMediaPlayer
    private let library: VLCLibrary
    private let log = ErrorLog()
    private var hasPlayed = false
    private var knownDefault: String?

    private(set) var state: MoviePlaybackState = .opening
    private(set) var timeMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var isPictureInPictureActive = false
    private var pictureInPicture: (any VLCPictureInPictureWindowControlling)?
    var onChange: (() -> Void)?

    init(input: Input) {
        library = VLCLibrary(options: [])
        player = VLCMediaPlayer(library: library)
        drawable = MovieDrawableView(controls: PictureInPictureControls(player: player))
        view = drawable
        super.init()
        view.backgroundColor = .black
        library.loggers = [log]
        player.delegate = self
        drawable.onReady = { [weak self] window in
            MainActor.assumeIsolatedOrHop {
                guard let self else { return }
                window.stateChangeEventHandler = { [weak self] isStarted in
                    MainActor.assumeIsolatedOrHop {
                        self?.isPictureInPictureActive = isStarted
                        self?.onChange?()
                    }
                }
                self.pictureInPicture = window
                self.onChange?()
            }
        }
        player.drawable = drawable
        player.videoFitMode = .smaller
        player.timeChangeUpdateInterval = 0.25
        let media: VLCMedia?
        switch input {
        case .file(let url):
            media = VLCMedia(url: url)
        case .stream(let stream, let fileName):
            media = VLCMedia(stream: stream)
            // S1: over the network VLC only trusts Matroska Cues with this
            // demux; without it a seek decodes from the start.
            if ["mkv", "mka", "mk3d", "webm"].contains((fileName as NSString).pathExtension.lowercased()) {
                media?.addOption(":demux=mkv_trusted")
            }
        }
        if let media {
            player.media = media
        } else {
            state = .failed(String(localized: "ShotDex couldn't open this file.", comment: "Movie player error: no media"))
        }
    }

    var rate: Double {
        get { Double(player.rate) }
        set { player.rate = Float(newValue) }
    }

    var audioTracks: [MovieAudioTrack] {
        player.audioTracks.map { track in
            MovieAudioTrack(
                id: track.trackId,
                language: track.language,
                name: track.trackDescription ?? (track.trackName.isEmpty ? nil : track.trackName),
                codec: track.codecName(),
                channels: track.audio.map { Int($0.channelsNumber) },
                isDefault: track.trackId == knownDefault
            )
        }
    }

    var videoSize: CGSize { player.videoSize }

    var fillsFrame: Bool {
        get { player.videoFitMode == .larger }
        set { player.videoFitMode = newValue ? .larger : .smaller }
    }

    var canPictureInPicture: Bool { pictureInPicture != nil }

    func togglePictureInPicture() {
        if isPictureInPictureActive {
            pictureInPicture?.stopPictureInPicture()
        } else {
            pictureInPicture?.startPictureInPicture()
        }
    }

    var selectedAudioTrackId: String? {
        player.audioTracks.first(where: \.isSelected)?.trackId
    }

    var audioDelayMs: Int {
        get { player.currentAudioPlaybackDelay / 1000 }
        set { player.currentAudioPlaybackDelay = newValue * 1000 }
    }

    func play() {
        guard case .failed = state else {
            player.play()
            return
        }
    }

    func pause() { player.pause() }

    func seek(toMs ms: Int64) {
        player.time = VLCTime(int: Int32(clamping: max(0, ms)))
        timeMs = ms
        onChange?()
    }

    func selectAudioTrack(id: String) {
        // Exclusive: the old track stops, the clock does not (AC-15).
        player.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
        onChange?()
    }

    func close() {
        if isPictureInPictureActive { pictureInPicture?.stopPictureInPicture() }
        pictureInPicture = nil
        player.stop()
        player.delegate = nil
        player.media = nil
    }

    /// The decoder or demuxer VLC complained about, in the user's words.
    private func failureReason() -> String {
        let lines = log.lines()
        if let line = lines.last(where: { $0.contains("no suitable decoder module for") }),
           let fourcc = line.firstMatch(of: #/fourcc `?([A-Za-z0-9 ]{1,4})'?/#)?.1 {
            return String(localized: "The \(fourcc.trimmingCharacters(in: .whitespaces).uppercased()) format isn't supported.", comment: "Movie player error: codec not supported")
        }
        if lines.contains(where: { $0.contains("cannot find any cluster") || $0.contains("damaged") || $0.contains("cannot peek") }) {
            return String(localized: "The file is damaged or incomplete.", comment: "Movie player error: corrupt file")
        }
        return String(localized: "ShotDex couldn't read this file.", comment: "Movie player error: other")
    }
}

extension VLCMoviePlayer: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        MainActor.assumeIsolatedOrHop {
            self.apply(newState)
            self.pictureInPicture?.invalidatePlaybackState()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        MainActor.assumeIsolatedOrHop {
            self.timeMs = Int64(self.player.time.intValue)
            if self.durationMs == 0, let length = self.player.media?.length.intValue, length > 0 { self.durationMs = Int64(length) }
            self.onChange?()
        }
    }

    nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        MainActor.assumeIsolatedOrHop {
            self.durationMs = length
            self.onChange?()
        }
    }

    nonisolated func mediaPlayerBufferingChanged(_ progress: Float) {
        MainActor.assumeIsolatedOrHop {
            guard self.state == .playing || self.state == .buffering else { return }
            self.state = progress < 100 ? .buffering : .playing
            self.onChange?()
        }
    }

    private func apply(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            state = .opening
        case .playing:
            hasPlayed = true
            if knownDefault == nil { knownDefault = player.audioTracks.first(where: \.isSelected)?.trackId }
            state = .playing
        case .paused:
            state = .paused
        case .stopped:
            if hasPlayed, durationMs > 0, timeMs >= durationMs - 1_500 {
                state = .ended
            } else if !hasPlayed {
                state = .failed(failureReason())
            } else {
                state = .ended
            }
        case .error:
            state = .failed(failureReason())
        case .stopping, .nothingSpecial:
            return
        @unknown default:
            return
        }
        onChange?()
    }
}

/// The view VLC draws into, and the hook its picture-in-picture uses: VLCKit
/// builds the PiP window itself once the drawable offers controls.
private final class MovieDrawableView: UIView, VLCPictureInPictureDrawable {
    private let controls: PictureInPictureControls
    var onReady: ((any VLCPictureInPictureWindowControlling) -> Void)?

    init(controls: PictureInPictureControls) {
        self.controls = controls
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func mediaController() -> (any VLCPictureInPictureMediaControlling)! { controls }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        { [weak self] window in
            guard let window else { return }
            self?.onReady?(window)
        }
    }
}

/// Play, pause and ±10 s from the PiP window. VLC calls these on its own
/// threads; `VLCMediaPlayer` is safe to drive from any of them.
private final class PictureInPictureControls: NSObject, VLCPictureInPictureMediaControlling, @unchecked Sendable {
    private weak var player: VLCMediaPlayer?

    init(player: VLCMediaPlayer) { self.player = player }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(by offset: Int64, completion: (() -> Void)!) {
        if let player { player.time = VLCTime(int: Int32(clamping: Int64(player.time.intValue) + offset)) }
        completion?()
    }
    func mediaLength() -> Int64 { Int64(player?.media?.length.intValue ?? 0) }
    func mediaTime() -> Int64 { Int64(player?.time.intValue ?? 0) }
    func isMediaSeekable() -> Bool { player?.isSeekable ?? false }
    func isMediaPlaying() -> Bool { player?.isPlaying ?? false }
}

/// VLC's error lines, kept for the one-line reason (FS-23.02 §2). Passwords
/// never reach VLC (S1), so nothing secret is logged here.
private final class ErrorLog: NSObject, VLCLogging, @unchecked Sendable {
    var level: VLCLogLevel = .error
    private let store = OSAllocatedUnfairLock(initialState: [String]())

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        store.withLock {
            $0.append(message)
            if $0.count > 40 { $0.removeFirst($0.count - 40) }
        }
    }

    func lines() -> [String] { store.withLock { $0 } }
}

private extension MainActor {
    /// VLCKit delivers delegate calls on the main thread; this keeps that
    /// promise checked and hops if it ever changes.
    static func assumeIsolatedOrHop(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
