import AVFoundation
import CoreMedia
import ImageIO
import Photos
import SwiftUI
import os

/// What the video page should show. The viewer previously had only "player is
/// nil" vs "player exists", which is why an item that arrived but never became
/// renderable produced a permanently black screen with no spinner, no error and
/// no way to retry.
enum VideoPlaybackPhase: Equatable {
    case idle
    /// PhotoKit is pulling the clip from iCloud; `Double` is 0…1.
    case downloading(Double)
    /// The item exists but has no displayable frame yet (initial load, or a
    /// mid-playback stall).
    case buffering
    case ready
    /// Human-readable reason plus an implied Retry affordance.
    case failed(String)

    var isReady: Bool { self == .ready }
}

/// Outcome of "Save Frame to Photos", surfaced as a short confirmation.
enum VideoFrameSaveOutcome: Equatable {
    case saved
    case failed(String)
}

/// Owns one video page's `AVPlayer` and everything around it: the PhotoKit
/// request, readiness/failure classification, the transport's derived state,
/// and the extra transport actions (rate, loop, frame step, frame export).
///
/// Why a controller and not `@State` in the page view: the state machine needs
/// KVO observers, a notification observer, a periodic time observer, a stall
/// watchdog task and a cancellable PhotoKit request id, all with a single
/// teardown point. Spreading that across `@State` in `PhotoDetailScreen.swift`
/// (already 2000+ lines) is how the silent-failure paths got there in the first
/// place.
@MainActor
@Observable
final class VideoPlaybackController {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "video")

    /// Matches the image path's iCloud stall window (`PhotoDetailScreen`), so a
    /// video that never becomes playable reports in at the same point a stuck
    /// photo download does.
    private static let readinessTimeout: Duration = .seconds(15)
    /// Relative seek applied by a double-tap on either half of the surface.
    static let skipInterval: Double = 10

    // MARK: Observable state

    private(set) var player: AVPlayer?
    private(set) var phase: VideoPlaybackPhase = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var isMuted: Bool
    private(set) var rate: Double
    private(set) var isLooping: Bool
    /// Nominal frame rate of the video track, for single-frame stepping.
    private(set) var frameRate: Double = VideoTransportMath.fallbackFrameRate
    private(set) var isScrubbing = false
    private(set) var scrubTime: Double = 0
    private(set) var isSavingFrame = false
    private(set) var frameSaveOutcome: VideoFrameSaveOutcome?

    /// Slider range's upper bound — never collapses, and always contains the
    /// bound value even before an iCloud item's duration resolves.
    var timelineUpperBound: Double {
        VideoTransportMath.timelineUpperBound(
            duration: duration,
            current: currentTime,
            scrub: scrubTime
        )
    }

    var displayTime: Double { isScrubbing ? scrubTime : currentTime }

    // MARK: Dependencies / plumbing

    @ObservationIgnored private weak var photoLibrary: PhotoLibraryService?
    @ObservationIgnored private var asset: PHAsset?
    /// Forwarded iCloud progress, so the viewer's existing info-panel download
    /// ring and 15 s stall warning finally cover videos too.
    @ObservationIgnored private var onDownloadProgress: ((Double, Bool) -> Void)?

    @ObservationIgnored private var requestId: PHImageRequestID?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var readinessWatchdog: Task<Void, Never>?
    @ObservationIgnored private var trackLoadTask: Task<Void, Never>?
    @ObservationIgnored private var frameSaveTask: Task<Void, Never>?

    /// The two halves of "renderable": the item can play, and the layer has a
    /// frame. Both are required before the overlay is dismissed — that gate is
    /// the direct fix for "player exists but the screen is black".
    @ObservationIgnored private var isItemReady = false
    @ObservationIgnored private var isLayerReady = false
    /// Set once the video track is known to exist. An audio-only `.mov` never
    /// reports `isReadyForDisplay`, so it must not be gated on the layer.
    @ObservationIgnored private var hasVideoTrack = true
    @ObservationIgnored private var didActivateAudioSession = false
    /// A `play()` that arrived before the item did. Video pages autoplay like
    /// Photos, and the request usually finishes *after* the page appears, so the
    /// intent has to be remembered rather than dropped.
    @ObservationIgnored private var autoplayPending = false

    // MARK: Persisted preferences

    private enum Defaults {
        static let rate = "videoPlaybackRate"
        static let loop = "videoLoopEnabled"
        static let startsMuted = "videoStartsMuted"
    }

    init(defaults: UserDefaults = .standard) {
        let storedRate = defaults.double(forKey: Defaults.rate)
        rate = Self.supportedRates.contains(storedRate) ? storedRate : 1
        isLooping = defaults.bool(forKey: Defaults.loop)
        // Photos-style: video pages start muted, and the choice sticks for the
        // rest of the session's browsing.
        isMuted = defaults.object(forKey: Defaults.startsMuted) as? Bool ?? true
    }

    static let supportedRates: [Double] = [0.5, 1, 1.5, 2]

    // MARK: Lifecycle

    func configure(
        asset: PHAsset,
        photoLibrary: PhotoLibraryService,
        onDownloadProgress: @escaping (Double, Bool) -> Void
    ) {
        self.asset = asset
        self.photoLibrary = photoLibrary
        self.onDownloadProgress = onDownloadProgress
    }

    /// Starts the PhotoKit request. Callers must only invoke this for the page
    /// that is actually on screen: `UIPageViewController` builds neighbours
    /// eagerly, and three concurrent whole-video iCloud downloads starve the one
    /// the user is looking at.
    func load() {
        guard player == nil, requestId == nil, let asset, let photoLibrary else { return }
        phase = .buffering
        onDownloadProgress?(0, true)
        armReadinessWatchdog()
        requestId = photoLibrary.requestPlayerItem(
            for: asset,
            progress: { [weak self] value in
                self?.handleDownloadProgress(value)
            },
            completion: { [weak self] result in
                self?.handleRequestResult(result)
            }
        )
    }

    /// `tearDown` deliberately keeps the configured asset/library/callback, so a
    /// retry is a clean restart of the request without re-plumbing the page.
    func retry() {
        tearDown()
        load()
    }

    func tearDown() {
        readinessWatchdog?.cancel()
        readinessWatchdog = nil
        trackLoadTask?.cancel()
        trackLoadTask = nil
        frameSaveTask?.cancel()
        frameSaveTask = nil
        if let requestId {
            photoLibrary?.cancelVideoRequest(requestId)
        }
        requestId = nil
        removeTimeObserver()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        endObserver = nil
        failureObserver = nil
        player?.pause()
        player = nil
        releaseAudioSession()
        isItemReady = false
        isLayerReady = false
        hasVideoTrack = true
        isPlaying = false
        currentTime = 0
        scrubTime = 0
        duration = 0
        isScrubbing = false
        frameSaveOutcome = nil
        isSavingFrame = false
        autoplayPending = false
        phase = .idle
        onDownloadProgress?(0, false)
    }

    // MARK: Request handling

    private func handleDownloadProgress(_ value: Double) {
        // Progress means the pipe is alive: restart the timeout rather than
        // failing a large clip on a slow connection.
        armReadinessWatchdog()
        if value < 1 {
            phase = .downloading(value)
        } else if case .downloading = phase {
            phase = .buffering
        }
        onDownloadProgress?(value, true)
    }

    private func handleRequestResult(_ result: Result<AVPlayerItem, Error>) {
        requestId = nil
        onDownloadProgress?(1, false)
        switch result {
        case .success(let item):
            attach(item)
        case .failure(let error):
            Self.logger.error("player item request failed: \(error.localizedDescription)")
            fail(with: error)
        }
    }

    private func attach(_ item: AVPlayerItem) {
        // A couple of seconds of read-ahead is enough for the viewer and keeps
        // memory down on 4K/ProRes clips.
        item.preferredForwardBufferDuration = 2
        // Otherwise 2× playback sounds like a chipmunk.
        item.audioTimePitchAlgorithm = .timeDomain

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = isMuted
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.actionAtItemEnd = isLooping ? .none : .pause
        avPlayer.defaultRate = Float(rate)
        player = avPlayer

        phase = .buffering
        installObservers(on: avPlayer, item: item)
        installTimeObserver(on: avPlayer)
        loadTrackInfo(for: item)
        armReadinessWatchdog()
    }

    private func fail(with error: Error) {
        readinessWatchdog?.cancel()
        readinessWatchdog = nil
        onDownloadProgress?(0, false)
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        phase = .failed(message.isEmpty ? "This video couldn’t be played." : message)
    }

    /// Fires when nothing has become renderable for `readinessTimeout`. Without
    /// it a request that neither succeeds nor errors — the actual reported
    /// symptom — leaves the page spinning forever.
    private func armReadinessWatchdog() {
        readinessWatchdog?.cancel()
        readinessWatchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.readinessTimeout)
            guard !Task.isCancelled, let self, !self.phase.isReady else { return }
            self.onDownloadProgress?(0, false)
            self.phase = .failed("This video is taking too long to load.")
        }
    }

    // MARK: Observation

    private func installObservers(on avPlayer: AVPlayer, item: AVPlayerItem) {
        // Only Sendable scalars cross out of the KVO callbacks; anything that
        // needs the item itself is re-read on the main actor.
        observations.append(
            item.observe(\.status, options: [.initial, .new]) { [weak self] _, change in
                let raw = change.newValue?.rawValue
                Task { @MainActor in self?.handleItemStatus(raw) }
            }
        )
        observations.append(
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, change in
                let value = change.newValue
                Task { @MainActor in self?.handleLikelyToKeepUp(value) }
            }
        )
        observations.append(
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, change in
                let value = change.newValue
                Task { @MainActor in self?.handleBufferEmpty(value) }
            }
        )
        observations.append(
            avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, change in
                let raw = change.newValue?.rawValue
                Task { @MainActor in self?.handleTimeControlStatus(raw) }
            }
        )

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePlayedToEnd() }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                self?.fail(with: error ?? PhotoVideoError.unavailable)
            }
        }
    }

    private func handleItemStatus(_ rawStatus: Int?) {
        guard let rawStatus, let status = AVPlayerItem.Status(rawValue: rawStatus) else { return }
        switch status {
        case .readyToPlay:
            isItemReady = true
            promoteToReadyIfPossible()
        case .failed:
            fail(with: player?.currentItem?.error ?? PhotoVideoError.unavailable)
        case .unknown:
            isItemReady = false
        @unknown default:
            break
        }
    }

    private func handleLikelyToKeepUp(_ value: Bool?) {
        guard value == true else { return }
        isItemReady = true
        promoteToReadyIfPossible()
    }

    private func handleBufferEmpty(_ value: Bool?) {
        // A mid-playback stall: keep the last frame but put the spinner back so
        // the pause never reads as a frozen app.
        guard value == true, phase.isReady else { return }
        phase = .buffering
    }

    private func handleTimeControlStatus(_ rawStatus: Int?) {
        guard let rawStatus,
              let status = AVPlayer.TimeControlStatus(rawValue: rawStatus)
        else { return }
        isPlaying = status == .playing
        if status == .playing {
            promoteToReadyIfPossible()
        }
    }

    /// Reported by the player layer's own `isReadyForDisplay` observation.
    func noteReadyForDisplay(_ ready: Bool) {
        isLayerReady = ready
        if ready {
            promoteToReadyIfPossible()
        }
    }

    private func promoteToReadyIfPossible() {
        guard isItemReady, isLayerReady || !hasVideoTrack else { return }
        readinessWatchdog?.cancel()
        readinessWatchdog = nil
        onDownloadProgress?(1, false)
        phase = .ready
        if autoplayPending {
            play()
        }
    }

    private func handlePlayedToEnd() {
        guard let player else { return }
        if isLooping {
            player.seek(to: .zero)
            currentTime = 0
            scrubTime = 0
            player.play()
            applyRate()
        } else {
            player.seek(to: .zero)
            currentTime = 0
            scrubTime = 0
            isPlaying = false
        }
    }

    private func installTimeObserver(on avPlayer: AVPlayer) {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite, !self.isScrubbing {
                    self.currentTime = max(0, seconds)
                }
                if let item = self.player?.currentItem {
                    let itemDuration = CMTimeGetSeconds(item.duration)
                    if itemDuration.isFinite, itemDuration > 0 {
                        self.duration = itemDuration
                    }
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    /// Frame rate (for stepping) and whether there is a video track at all (an
    /// audio-only `.mov` must not wait for `isReadyForDisplay`).
    private func loadTrackInfo(for item: AVPlayerItem) {
        trackLoadTask?.cancel()
        let asset = item.asset
        trackLoadTask = Task { [weak self] in
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            var nominal: Float?
            if let track = tracks.first {
                nominal = try? await track.load(.nominalFrameRate)
            }
            let assetDuration = try? await asset.load(.duration)
            guard !Task.isCancelled, let self else { return }
            self.hasVideoTrack = !tracks.isEmpty
            if let nominal, nominal > 0 {
                self.frameRate = Double(nominal)
            }
            if let assetDuration {
                let seconds = CMTimeGetSeconds(assetDuration)
                if seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
            }
            self.promoteToReadyIfPossible()
        }
    }

    // MARK: Transport

    func play() {
        guard let player else {
            autoplayPending = true
            return
        }
        autoplayPending = false
        player.play()
        applyRate()
        isPlaying = true
    }

    func pause() {
        autoplayPending = false
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        UserDefaults.standard.set(muted, forKey: Defaults.startsMuted)
        // The audio session is only claimed once the user actually wants sound:
        // browsing muted must not interrupt whatever is already playing.
        if muted {
            releaseAudioSession()
        } else {
            claimAudioSession()
        }
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        UserDefaults.standard.set(newRate, forKey: Defaults.rate)
        player?.defaultRate = Float(newRate)
        applyRate()
    }

    func setLooping(_ looping: Bool) {
        isLooping = looping
        UserDefaults.standard.set(looping, forKey: Defaults.loop)
        player?.actionAtItemEnd = looping ? .none : .pause
    }

    /// `defaultRate` alone is not enough — an in-flight `play()` keeps the old
    /// rate until it is written directly.
    private func applyRate() {
        guard let player, player.timeControlStatus != .paused else { return }
        player.rate = Float(rate)
    }

    func beginScrub() {
        scrubTime = currentTime
        isScrubbing = true
    }

    func endScrub() {
        seek(to: scrubTime, precise: true)
        isScrubbing = false
    }

    func updateScrub(_ value: Double) {
        scrubTime = value
    }

    /// Double-tap ±10 s. Tolerance is loose on purpose: a sample-accurate seek
    /// re-decodes from the previous keyframe and makes the gesture feel sticky.
    func skip(by delta: Double) {
        let target = VideoTransportMath.seekTarget(
            current: displayTime,
            duration: duration,
            delta: delta
        )
        seek(to: target, precise: false)
    }

    /// One frame in `direction`. Zero tolerance is required here, otherwise the
    /// seek lands back on the frame it started from.
    func stepFrame(_ direction: Int) {
        let target = VideoTransportMath.frameStepTarget(
            current: displayTime,
            frameRate: frameRate,
            direction: direction,
            duration: duration
        )
        pause()
        seek(to: target, precise: true)
    }

    private func seek(to seconds: Double, precise: Bool) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance: CMTime = precise
            ? .zero
            : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = seconds
        scrubTime = seconds
    }

    // MARK: Frame export

    /// Exports the frame currently on screen into the photo library at full
    /// resolution — the one thing a photographer wants out of a clip that a
    /// screenshot cannot give them.
    func saveCurrentFrame() {
        guard !isSavingFrame, let item = player?.currentItem else { return }
        let avAsset = item.asset
        let phAsset = asset
        let seconds = displayTime
        let rate = frameRate
        isSavingFrame = true
        frameSaveOutcome = nil
        frameSaveTask = Task { [weak self] in
            do {
                let export = try await Self.exportFrame(from: avAsset, at: seconds)
                let filename = VideoTransportMath.frameFilename(
                    base: await Self.originalFilename(for: phAsset),
                    seconds: export.actualSeconds,
                    frameRate: rate,
                    fileExtension: export.fileExtension
                )
                guard !Task.isCancelled, let library = self?.photoLibrary else { return }
                _ = try await library.saveImage(export.data, filename: filename)
                guard !Task.isCancelled else { return }
                self?.isSavingFrame = false
                self?.frameSaveOutcome = .saved
            } catch {
                Self.logger.error("frame export failed: \(error.localizedDescription)")
                guard !Task.isCancelled else { return }
                self?.isSavingFrame = false
                self?.frameSaveOutcome = .failed("Couldn’t save this frame.")
            }
        }
    }

    func clearFrameSaveOutcome() {
        frameSaveOutcome = nil
    }

    /// The clip's own filename, so the exported frame is recognizably a grab from
    /// it. Read off the main actor — resource enumeration can hit the on-demand
    /// original-metadata fetch.
    private nonisolated static func originalFilename(for asset: PHAsset?) async -> String? {
        guard let asset else { return nil }
        return PHAssetResource.assetResources(for: asset).first?.originalFilename
    }

    /// `nonisolated` so the decode *and* the full-resolution HEIC encode stay off
    /// the main actor — a 4K/ProRes frame is far too expensive to encode there.
    private nonisolated static func exportFrame(
        from asset: AVAsset,
        at seconds: Double
    ) async throws -> (data: Data, fileExtension: String, actualSeconds: Double) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // The exported frame must be the one on screen, not the nearest keyframe.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Full sensor resolution, not the display size.
        generator.maximumSize = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let (cgImage, actualTime) = try await generator.image(at: time)
        guard let encoded = encode(cgImage) else { throw PhotoVideoError.unavailable }
        return (encoded.data, encoded.fileExtension, CMTimeGetSeconds(actualTime))
    }

    /// HEIC keeps a 4K/ProRes grab close to lossless at a fraction of the size;
    /// JPEG is the fallback for anything the encoder refuses.
    private nonisolated static func encode(
        _ cgImage: CGImage
    ) -> (data: Data, fileExtension: String)? {
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        for (type, ext) in [("public.heic", "heic"), ("public.jpeg", "jpg")] {
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                buffer,
                type as CFString,
                1,
                nil
            ) else { continue }
            CGImageDestinationAddImage(destination, cgImage, properties)
            if CGImageDestinationFinalize(destination) {
                return (buffer as Data, ext)
            }
        }
        return nil
    }

    // MARK: Audio session

    private func claimAudioSession() {
        guard !didActivateAudioSession else { return }
        didActivateAudioSession = true
        VideoAudioSession.activate()
    }

    private func releaseAudioSession() {
        guard didActivateAudioSession else { return }
        didActivateAudioSession = false
        VideoAudioSession.deactivate()
    }
}

/// Shared, reference-counted `.playback` session.
///
/// Without it, unmuting produced no sound at all while the ring/silent switch
/// was set to silent — the default `.soloAmbient` category is muted by that
/// switch. Reference counted because pager neighbours can each hold a
/// controller, and the last one out must be the one that hands audio focus back
/// (`.notifyOthersOnDeactivation` resumes whatever was playing before).
@MainActor
enum VideoAudioSession {
    private static var activations = 0

    static func activate() {
        activations += 1
        guard activations == 1 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    static func deactivate() {
        guard activations > 0 else { return }
        activations -= 1
        guard activations == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
