import AVFoundation
import Foundation
import Observation
import Photos

/// Hands Compare Videos a player item for a library video. PhotoKit on every
/// device; the Mac's demo hands it generated clips.
@MainActor
protocol VideoCompareLoading {
    func playerItem(for id: String) async -> AVPlayerItem?
}

/// Asks PhotoKit for the best version it has: a reduced stream would make
/// the original look worse than it is and the comparison a lie.
struct PhotoKitVideoCompareLoader: VideoCompareLoading {
    func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [id]).first, asset.mediaType == .video else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                // AVPlayerItem is built on the main actor; the asset crosses alone.
                nonisolated(unsafe) let avAsset = avAsset
                Task { @MainActor in
                    continuation.resume(returning: avAsset.map { AVPlayerItem(asset: $0) })
                }
            }
        }
    }
}

/// FS-24 §10 Compare Videos: the original (A) and its compressed copy (B) on
/// one clock. A is the master — its sound, its time; B is slaved to it and
/// moved back whenever it drifts past `VideoCompareRules.needsResync`.
/// Shared by iOS and the Mac; each draws its own panes and zoom.
@MainActor
@Observable
final class VideoCompareModel {
    let batch: VideoCompressionBatch
    private let loader: any VideoCompareLoading

    /// The pair on screen, by its original's id (indices shift as originals go).
    private(set) var currentID: String?
    let original = AVPlayer()
    let copy = AVPlayer()
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var frameRate: Double = 30
    /// "H.264", "HEVC"… of the original, once its track is read.
    private(set) var originalCodec: String?
    /// Width / height as shown (rotation applied), so a pane fits the
    /// picture and its label sits on it, not on a letterbox.
    private(set) var videoAspect: CGFloat = 16 / 9
    var isMuted = false {
        didSet { original.isMuted = isMuted }
    }
    /// Set while a Delete Original waits for PhotoKit.
    private(set) var isDeleting = false
    /// True once nothing is left to compare: the screen closes.
    private(set) var isEmpty = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?

    init(batch: VideoCompressionBatch, startID: String? = nil, loader: any VideoCompareLoading) {
        self.batch = batch
        self.loader = loader
        let pairs = batch.comparePairs
        currentID = pairs.first { $0.id == startID }?.id ?? pairs.first?.id
        isEmpty = currentID == nil
        // B never makes a sound: both carry the same AAC (FS-24 §1.3).
        copy.isMuted = true
        // Started together at a host time, so neither may wait on its own.
        original.automaticallyWaitsToMinimizeStalling = false
        copy.automaticallyWaitsToMinimizeStalling = false
        // The A pane is the master clock: every 1/30 s the scrubber reads it
        // and B is held to it.
        timeObserver = original.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    /// Call when the screen goes away: players stop, observers go.
    func tearDown() {
        loadTask?.cancel()
        original.pause()
        copy.pause()
        if let timeObserver { original.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        original.replaceCurrentItem(with: nil)
        copy.replaceCurrentItem(with: nil)
    }

    var pairs: [VideoCompareRules.Pair] { batch.comparePairs }

    var currentPair: VideoCompareRules.Pair? {
        pairs.first { $0.id == currentID }
    }

    /// 0-based position in `pairs`.
    var currentIndex: Int? {
        pairs.firstIndex { $0.id == currentID }
    }

    // MARK: Loading

    func loadCurrent() {
        loadTask?.cancel()
        pause()
        guard let pair = currentPair else { return }
        isLoading = true
        currentTime = 0
        duration = 0
        originalCodec = nil
        loadTask = Task {
            async let a = loader.playerItem(for: pair.id)
            async let b = loader.playerItem(for: pair.copyID)
            let (itemA, itemB) = await (a, b)
            guard !Task.isCancelled, currentID == pair.id else { return }
            original.replaceCurrentItem(with: itemA)
            copy.replaceCurrentItem(with: itemB)
            original.isMuted = isMuted
            observeEnd(of: itemA)
            if let asset = itemA?.asset {
                duration = (try? await asset.load(.duration).seconds) ?? 0
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let (rate, descriptions) = (try? await track.load(.nominalFrameRate, .formatDescriptions)) ?? (Float(30), [])
                    if let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                        let shown = CGRect(origin: .zero, size: size).applying(transform).size
                        if shown.width > 0, shown.height > 0 { videoAspect = abs(shown.width / shown.height) }
                    }
                    frameRate = rate > 0 ? Double(rate) : 30
                    originalCodec = descriptions.first.map { Self.codecName($0.mediaSubType.rawValue) }
                }
            }
            guard !Task.isCancelled, currentID == pair.id else { return }
            await seek(to: 0)
            isLoading = false
        }
    }

    private func observeEnd(of item: AVPlayerItem?) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        guard let item else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.copy.pause()
            }
        }
    }

    static func codecName(_ subtype: FourCharCode) -> String {
        switch subtype {
        case kCMVideoCodecType_H264: "H.264"
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: "HEVC"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ: "ProRes"
        case kCMVideoCodecType_AV1: "AV1"
        default: String(localized: "Video", comment: "Compare Videos: codec label when the format is not one we name")
        }
    }

    // MARK: Transport

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isLoading, original.currentItem != nil else { return }
        var start = original.currentTime()
        if duration > 0, start.seconds >= duration - 1 / frameRate { start = .zero }
        // Both start on the same host tick from the same time: they begin in step.
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 10))
        original.setRate(1, time: start, atHostTime: host)
        copy.setRate(1, time: start, atHostTime: host)
        isPlaying = true
    }

    func pause() {
        original.pause()
        copy.pause()
        isPlaying = false
        // Paused, both must show the same frame.
        let time = original.currentTime()
        copy.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(to seconds: Double) async {
        let clamped = min(max(seconds, 0), max(duration, 0))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        currentTime = clamped
        async let a: Bool = original.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        async let b: Bool = copy.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        _ = await (a, b)
    }

    /// Scrubbing: lands quickly while the finger moves, exactly when it lifts.
    func scrub(to seconds: Double, isFinal: Bool) {
        if isPlaying { pause() }
        if isFinal {
            Task { await seek(to: seconds) }
        } else {
            let time = CMTime(seconds: min(max(seconds, 0), duration), preferredTimescale: 600)
            currentTime = time.seconds
            let tolerance = CMTime(value: 1, timescale: 10)
            original.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
            copy.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
    }

    /// Previous/next frame on both.
    func stepFrame(_ count: Int) {
        if isPlaying { pause() }
        let target = original.currentTime().seconds + Double(count) / frameRate
        Task { await seek(to: target) }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        guard copy.currentItem != nil else { return }
        let drift = copy.currentTime().seconds - seconds
        if VideoCompareRules.needsResync(drift: drift, frameRate: frameRate, isPlaying: isPlaying) {
            if isPlaying {
                // Re-lock B to A's clock rather than seek it: no stutter on A.
                let host = CMClockGetTime(CMClockGetHostTimeClock())
                copy.setRate(1, time: original.currentTime(), atHostTime: host)
            } else {
                copy.seek(to: original.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    // MARK: Files

    var canStepBack: Bool {
        guard let index = currentIndex else { return false }
        return VideoCompareRules.index(after: index, step: -1, count: pairs.count) != nil
    }

    var canStepForward: Bool {
        guard let index = currentIndex else { return false }
        return VideoCompareRules.index(after: index, step: 1, count: pairs.count) != nil
    }

    func stepVideo(_ step: Int) {
        guard let index = currentIndex,
              let next = VideoCompareRules.index(after: index, step: step, count: pairs.count) else { return }
        currentID = pairs[next].id
        loadCurrent()
    }

    /// Delete Original (FS-24 §10): this pair's original only, through
    /// PhotoKit's confirmation; then the next pair, or the end.
    func deleteCurrentOriginal() async {
        guard let pair = currentPair, let index = currentIndex, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        pause()
        guard await batch.deleteOriginal(of: pair.id) else { return }
        let remaining = pairs
        guard let next = VideoCompareRules.index(afterRemoving: index, remaining: remaining.count) else {
            currentID = nil
            isEmpty = true
            original.replaceCurrentItem(with: nil)
            copy.replaceCurrentItem(with: nil)
            return
        }
        currentID = remaining[next].id
        loadCurrent()
    }
}
