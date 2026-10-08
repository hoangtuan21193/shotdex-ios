import CoreGraphics
import Foundation

/// What the pointer is skimming (FS-12.17b §6): the line under the frame
/// says it, the viewer shows it, the transport keeps the playhead's time.
struct VideoSkim: Equatable {
    var assetID: String
    var name: String
    /// Nil for a photo: its name only.
    var time: Double?
    var duration: Double?
    var isNotDownloaded = false

    /// "· Lake · 0:02.3 / 0:05".
    var detail: String {
        VideoSkimMath.detail(
            name: name, time: time, duration: duration,
            notDownloaded: isNotDownloaded, notDownloadedText: VideoStudioCopy.notDownloaded
        )
    }
}

extension VideoStudioModel {
    /// The pointer is `fraction` of the way across the cell of `assetID`.
    /// Playing, nothing is skimmed — the frame belongs to the playback.
    func skimMedia(assetID: String, name: String, isVideo: Bool, duration: Double, fraction: Double, thumbnail: CGImage?) {
        guard !isPlaying else {
            endSkim()
            return
        }
        let isNewSource = skim?.assetID != assetID
        if isNewSource {
            skimThrottle.reset()
            skimImage = thumbnail
        }
        guard isVideo else {
            skim = VideoSkim(assetID: assetID, name: name)
            return
        }
        let time = VideoSkimMath.time(fraction: fraction, duration: duration)
        var next = VideoSkim(assetID: assetID, name: name, time: time, duration: duration)
        next.isNotDownloaded = !isNewSource && skim?.isNotDownloaded == true
        skim = next
        skimThumbnail = thumbnail
        let now = Date.timeIntervalSinceReferenceDate
        if let ask = skimThrottle.offer(time, at: now) {
            requestSkimFrame(assetID: assetID, at: ask)
        } else {
            // Its turn comes in at most a thirtieth of a second; by then a
            // newer position may have replaced it.
            skimFlushTask?.cancel()
            skimFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(34))
                guard let self, !Task.isCancelled, self.skim?.assetID == assetID else { return }
                if let ask = self.skimThrottle.flush(at: Date.timeIntervalSinceReferenceDate) {
                    self.requestSkimFrame(assetID: assetID, at: ask)
                }
            }
        }
    }

    /// The pointer left the cell: the line and the viewer are the
    /// playhead's again, at once.
    func endSkim() {
        guard skim != nil || skimImage != nil else { return }
        skim = nil
        skimImage = nil
        skimThumbnail = nil
        skimTask?.cancel()
        skimFlushTask?.cancel()
        skimThrottle.reset()
        let source = skimSource
        Task { await source.reset() }
    }

    private func requestSkimFrame(assetID: String, at time: Double) {
        skimTask?.cancel()
        let source = skimSource
        skimTask = Task { @MainActor [weak self] in
            let frame = await source.frame(assetID: assetID, at: time, maximumSide: 1280)
            guard let self, !Task.isCancelled, self.skim?.assetID == assetID else { return }
            switch frame {
            case .image(let image):
                self.skimImage = image
            case .notDownloaded:
                // The thumbnail, and the line says why (§7).
                self.skim?.isNotDownloaded = true
                self.skimImage = self.skimThumbnail
            case .unavailable:
                break
            }
        }
    }
}
