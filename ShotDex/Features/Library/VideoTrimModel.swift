import AVFoundation
import Foundation
import Photos
import SwiftUI

/// State of the trim screen: the clip, the two handles, the preview loop, and
/// the write back to the library.
@MainActor
@Observable
final class VideoTrimModel {
    /// Frames on the strip. Enough to recognise where you are in the clip, few
    /// enough that generating them is not itself a wait.
    static let thumbnailCount = 10

    private(set) var player: AVPlayer?
    private(set) var duration: Double = 0
    private(set) var thumbnails: [CGImage] = []
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var isSaving = false
    var errorMessage: String?

    var start: Double = 0
    var end: Double = 0

    /// Which handle a drag took hold of, and where it started. Captured once
    /// per drag: re-deciding on every change would compound the offset and let
    /// the gesture jump between handles mid-move.
    private struct HandleDrag {
        let isStart: Bool
        let anchor: Double
        let grabX: CGFloat
    }

    private var dragInFlight: HandleDrag?
    private var avAsset: AVAsset?
    private var timeObserver: Any?
    private var requestId: PHImageRequestID = PHInvalidImageRequestID
    private weak var photoLibrary: PhotoLibraryService?
    private let trimService = VideoTrimService()

    var isTrimmed: Bool {
        VideoTrimMath.isTrimmed(start: start, end: end, duration: duration)
    }

    /// Saving is only offered for a range that actually changes something —
    /// writing the clip back untouched would still mark it edited.
    var canSave: Bool { isTrimmed && !isSaving && duration > 0 }

    var selectionLabel: String {
        guard duration > 0 else { return "—" }
        return "\(MetadataFormatter.duration(start)) – \(MetadataFormatter.duration(end))  ·  \(MetadataFormatter.duration(end - start))"
    }

    func load(asset: PHAsset, photoLibrary: PhotoLibraryService) async {
        self.photoLibrary = photoLibrary
        guard player == nil else { return }

        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            var hasResumed = false
            requestId = photoLibrary.requestPlayerItem(for: asset, progress: { _ in }) { result in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: try? result.get())
            }
        }
        guard let item else {
            errorMessage = "Couldn’t open this video."
            return
        }

        let avAsset = item.asset
        self.avAsset = avAsset
        let seconds = (try? await avAsset.load(.duration).seconds) ?? 0
        duration = seconds.isFinite ? seconds : 0
        start = 0
        end = duration

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        player = avPlayer
        installTimeObserver(on: avPlayer)

        let times = VideoTrimMath.thumbnailTimes(count: Self.thumbnailCount, duration: duration)
        thumbnails = await VideoTrimService.thumbnails(for: avAsset, times: times, maximumEdge: 240)
    }

    func tearDown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        if requestId != PHInvalidImageRequestID {
            photoLibrary?.cancelVideoRequest(requestId)
            requestId = PHInvalidImageRequestID
        }
    }

    // MARK: Transport

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Play the range, not the clip: starting outside the kept part
            // would preview something the user is in the middle of discarding.
            if currentTime < start || currentTime >= end - 0.05 {
                seek(to: start)
            }
            player.play()
            isPlaying = true
        }
    }

    private func installTimeObserver(on player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                // Stop at the out point rather than at the end of the clip.
                if self.isPlaying, time.seconds >= self.end {
                    player.pause()
                    self.isPlaying = false
                    self.seek(to: self.end)
                }
            }
        }
    }

    private func seek(to seconds: Double) {
        currentTime = seconds
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: Handles

    func position(of seconds: Double, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return width * CGFloat(min(max(seconds / duration, 0), 1))
    }

    /// Moves whichever handle the finger started nearest to.
    ///
    /// The cut follows the finger's *movement*, not its absolute position: a
    /// finger lands somewhere near a handle, and treating that spot as the cut
    /// point would make the range jump the moment it is touched.
    ///
    /// Playback stops while dragging: a preview running under a handle being
    /// moved shows the wrong frame for the thing the user is deciding.
    func dragHandle(toX x: CGFloat, from startX: CGFloat, width: CGFloat) {
        guard duration > 0, width > 0 else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
        let drag: HandleDrag
        if let dragInFlight {
            drag = dragInFlight
        } else {
            // Which handle was meant is decided once, at touch-down, and held
            // for the whole drag — otherwise dragging the start past the end
            // would hand the gesture to the other handle mid-move.
            let grabbed = Double(min(max(startX / width, 0), 1)) * duration
            let isStart = abs(grabbed - start) <= abs(grabbed - end)
            drag = HandleDrag(isStart: isStart, anchor: isStart ? start : end, grabX: startX)
            dragInFlight = drag
        }
        let delta = Double((x - drag.grabX) / width) * duration
        apply(isStart: drag.isStart, seconds: drag.anchor + delta)
    }

    /// VoiceOver's increment/decrement, in steps a person can hear the result
    /// of rather than one frame at a time.
    func nudgeHandle(isStart: Bool, forward: Bool) {
        let step = max(duration / 40, 0.1)
        let current = isStart ? start : end
        apply(isStart: isStart, seconds: current + (forward ? step : -step))
    }

    private func apply(isStart: Bool, seconds: Double) {
        let clamped = VideoTrimMath.clamped(
            start: isStart ? seconds : start,
            end: isStart ? end : seconds,
            duration: duration,
            movingStart: isStart
        )
        start = clamped.start
        end = clamped.end
        // The frame under the handle is the whole point of dragging it.
        seek(to: isStart ? start : end)
    }

    func endHandleDrag() {
        dragInFlight = nil
        seek(to: start)
    }

    func reset() {
        start = 0
        end = duration
        seek(to: 0)
    }

    // MARK: Save

    func save(asset: PHAsset) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        player?.pause()
        isPlaying = false
        defer { isSaving = false }
        do {
            try await trimService.trim(asset, to: .init(start: start, end: end))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
