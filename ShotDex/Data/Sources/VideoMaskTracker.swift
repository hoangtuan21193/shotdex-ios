import AVFoundation
import CoreGraphics
import Foundation
import Photos
import Vision
import ShotDexKit

/// Follows a power window across a shot with Vision's object tracker.
///
/// The job Resolve's tracker does: you put a window on a face, press track,
/// and the window goes where the face goes. This does the same with
/// `VNTrackObjectRequest`, which is the tracker iOS actually ships — fed one
/// frame at a time through a `VNSequenceRequestHandler`, starting from the
/// box the window is drawn on.
///
/// **What it recovers is position and size, and nothing else.** Vision
/// returns an axis-aligned bounding box; rotation, perspective and shear are
/// not in it. A planar track is a different algorithm and a different
/// feature, and pretending an axis-aligned box is one would produce windows
/// that drift off a tilting subject while looking like they worked.
///
/// Frames are sampled at `sampleRate`, not at the video's own rate: the
/// tracker is measuring where something is, and 12 samples a second is enough
/// to interpolate between when the result is a soft-edged gradient. It also
/// keeps a 20-second shot to a few hundred inferences instead of a few
/// thousand.
actor VideoMaskTracker {
    enum Failure: Error, Equatable {
        case notTrackable
        case assetUnavailable
        case noVideoTrack
        case cancelled
    }

    /// Samples per second of source. Twelve is two frames of slack at 24fps
    /// and the interpolation covers the gap.
    static let sampleRate: Double = 12

    /// Vision's tracker degrades over a long run — it is meant to be reseeded.
    /// Past this many seconds the track stops and says where it got to rather
    /// than drifting quietly.
    static let maximumDuration: Double = 30

    /// Tracks `mask` through `clip`, reporting progress 0…1 as it goes.
    ///
    /// `clipStart` is where the clip sits on the project timeline, so the
    /// keyframes come back in project time and the compositor can look one up
    /// without knowing anything about clips.
    func track(
        mask: PhotoMask,
        assetID: String,
        clipStart: Double,
        trimStart: Double,
        duration: Double,
        renderSize: CGSize,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> MaskTrack {
        guard let component = mask.components.first,
              MaskTrackMath.isTrackable(component.kind)
        else { throw Failure.notTrackable }

        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first,
              let avAsset = await Self.loadAVAsset(asset)
        else { throw Failure.assetUnavailable }

        guard let videoTrack = try? await avAsset.loadTracks(withMediaType: .video).first
        else { throw Failure.noVideoTrack }

        let reader = try AVAssetReader(asset: avAsset)
        let span = min(duration, Self.maximumDuration)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: span, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.noVideoTrack }
        reader.add(output)
        reader.startReading()

        // Vision's box is the unit rectangle with the origin at the
        // **bottom** left; the window's normalized point has it at the top.
        let start = Self.visionRect(for: component, renderSize: renderSize)
        var observation = VNDetectedObjectObservation(boundingBox: start)
        let handler = VNSequenceRequestHandler()

        var keyframes: [MaskKeyframe] = [MaskKeyframe(time: clipStart)]
        var lastSampled = -Double.infinity
        let interval = 1 / Self.sampleRate

        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sample = output.copyNextSampleBuffer() else { break }
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds - trimStart
            guard seconds - lastSampled >= interval else { continue }
            lastSampled = seconds
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            // Tracking accuracy costs time and this runs while the user
            // waits, with a progress bar in front of them.
            request.trackingLevel = .fast
            do {
                try handler.perform([request], on: buffer)
            } catch {
                break
            }
            guard let result = request.results?.first as? VNDetectedObjectObservation,
                  result.confidence > 0.3
            else { break }
            observation = result

            keyframes.append(
                Self.keyframe(
                    from: start,
                    to: result.boundingBox,
                    at: clipStart + seconds
                )
            )
            onProgress(min(1, seconds / max(span, 0.001)))
        }
        reader.cancelReading()
        try Task.checkCancellation()

        onProgress(1)
        return MaskTrack(maskID: mask.id, keyframes: keyframes)
    }

    // MARK: Geometry

    /// The window's own shape as a Vision bounding box.
    ///
    /// A radial window is an ellipse; the tracker wants the box around it. A
    /// linear window has no area, so it is given a box around its two
    /// handles — what is being followed there is the edge, and its midpoint
    /// is what the track moves.
    nonisolated static func visionRect(
        for component: PhotoMaskComponent,
        renderSize: CGSize
    ) -> CGRect {
        // Aspect matters: a normalized radius is a fraction of *each* axis,
        // so a circle on a 16:9 frame is a wide ellipse in pixels, and the
        // box has to be the one Vision will see.
        switch component.kind {
        case .linearGradient:
            let minX = min(component.startPoint.x, component.endPoint.x)
            let maxX = max(component.startPoint.x, component.endPoint.x)
            let minY = min(component.startPoint.y, component.endPoint.y)
            let maxY = max(component.startPoint.y, component.endPoint.y)
            return flipped(
                CGRect(
                    x: minX, y: minY,
                    width: max(0.02, maxX - minX),
                    height: max(0.02, maxY - minY)
                )
            )
        default:
            return flipped(
                CGRect(
                    x: component.center.x - component.radiusX,
                    y: component.center.y - component.radiusY,
                    width: max(0.02, component.radiusX * 2),
                    height: max(0.02, component.radiusY * 2)
                )
            )
        }
    }

    /// Top-left origin to Vision's bottom-left, clamped into the unit square
    /// — Vision rejects a seed box that leaves it.
    private nonisolated static func flipped(_ rect: CGRect) -> CGRect {
        let x = min(max(0, rect.minX), 1)
        let width = min(max(0.02, rect.width), 1 - x)
        let height = min(max(0.02, rect.height), 1)
        let y = min(max(0, 1 - rect.maxY), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The delta between where the window was seeded and where the tracker
    /// says it is now — in the window's own top-left coordinates.
    nonisolated static func keyframe(
        from start: CGRect,
        to current: CGRect,
        at time: Double
    ) -> MaskKeyframe {
        let scale = start.width > 0.0001
            ? Double(current.width / start.width)
            : 1
        return MaskKeyframe(
            time: time,
            offsetX: Double(current.midX - start.midX),
            // Back to top-left: Vision's y runs the other way, so a box that
            // rose on screen has a *smaller* y here.
            offsetY: Double(start.midY - current.midY),
            scale: min(4, max(0.1, scale))
        )
    }

    private static func loadAVAsset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            // A proxy is fine for tracking — it is measuring where a thing is,
            // not how it looks — but the original must not be downloaded over
            // cellular behind the user's back.
            options.isNetworkAccessAllowed = false
            options.version = .current
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }
}
