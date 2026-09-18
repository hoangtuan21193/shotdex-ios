import AVFoundation
import Foundation
import Photos
import os

/// Pure arithmetic of a trim range, so the rules can be tested without a clip.
enum VideoTrimMath {
    /// Shortest clip a trim may produce. Below about a third of a second the
    /// result is a glitch rather than a video, and the handles become
    /// impossible to place.
    static let minimumDuration: Double = 0.3

    /// Keeps `start` and `end` inside the clip, in order, and at least
    /// `minimumDuration` apart. `movingStart` says which handle the user has
    /// hold of; the other one is what gives way when they collide.
    static func clamped(
        start: Double,
        end: Double,
        duration: Double,
        movingStart: Bool
    ) -> (start: Double, end: Double) {
        guard duration > minimumDuration else { return (0, duration) }
        var newStart = min(max(start, 0), duration)
        var newEnd = min(max(end, 0), duration)
        if movingStart {
            newStart = min(newStart, duration - minimumDuration)
            newEnd = max(newEnd, newStart + minimumDuration)
        } else {
            newEnd = max(newEnd, minimumDuration)
            newStart = min(newStart, newEnd - minimumDuration)
        }
        return (newStart, newEnd)
    }

    /// Whether this range is worth writing back. A trim that keeps the whole
    /// clip should not spend an export or add an "edited" badge.
    static func isTrimmed(start: Double, end: Double, duration: Double) -> Bool {
        start > 0.05 || end < duration - 0.05
    }

    /// Where a thumbnail belongs along the strip: `count` frames spread evenly
    /// across the clip, first at 0 and last just short of the end.
    static func thumbnailTimes(count: Int, duration: Double) -> [Double] {
        guard count > 1, duration > 0 else { return [0] }
        return (0..<count).map { index in
            duration * Double(index) / Double(count - 1) * 0.98
        }
    }
}

enum VideoTrimError: LocalizedError {
    case notAVideo
    case cannotRead
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAVideo: "This item is not a video."
        case .cannotRead: "Couldn’t open this video."
        case .exportFailed(let reason): reason
        }
    }
}

/// Trims a video in place, the way Photos' own trim does: the library keeps the
/// original, the trimmed version becomes what everything shows, and Revert
/// brings the full clip back.
///
/// In place rather than "save as new clip": a trim is a correction to one
/// video, and a library that answers it with a second copy is the thing people
/// complain about. `PHContentEditingOutput` carries the adjustment data that
/// makes the original recoverable, which is what earns the right to overwrite.
struct VideoTrimService: Sendable {
    /// Marks the result as ours, so a later session can recognise its own edit
    /// — and so Photos knows there is something to revert.
    static let formatIdentifier = "com.hoangtuan.shotdex.videotrim"
    static let formatVersion = "1.0"

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "VideoTrim")

    /// Range the trim is expressed in, in seconds from the start of the clip.
    struct Range: Equatable, Sendable, Codable {
        var start: Double
        var end: Double
    }

    func trim(_ asset: PHAsset, to range: Range) async throws {
        guard asset.mediaType == .video else { throw VideoTrimError.notAVideo }

        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // Accept our own earlier trim as a base, so trimming twice narrows the
        // clip further instead of being refused.
        options.canHandleAdjustmentData = { data in
            data.formatIdentifier == Self.formatIdentifier
                && data.formatVersion == Self.formatVersion
        }

        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input {
                    continuation.resume(returning: input)
                } else {
                    continuation.resume(throwing: VideoTrimError.cannotRead)
                }
            }
        }

        guard let avAsset = input.audiovisualAsset else { throw VideoTrimError.cannotRead }

        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: Self.formatIdentifier,
            formatVersion: Self.formatVersion,
            data: (try? JSONEncoder().encode(range)) ?? Data()
        )

        try await Self.export(avAsset, range: range, to: output.renderedContentURL)

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).contentEditingOutput = output
        }
    }

    /// A passthrough export of one time range.
    ///
    /// `AVAssetExportPresetPassthrough` keeps the original codec, bitrate and
    /// HDR metadata — a trim should cost the clip nothing but its ends, and
    /// re-encoding a ProRes or Dolby Vision capture to H.264 to remove two
    /// seconds would be a quiet act of damage.
    private static func export(
        _ asset: AVAsset,
        range: Range,
        to url: URL
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw VideoTrimError.exportFailed("Couldn’t start the export.")
        }
        let timescale: CMTimeScale = 600
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: timescale),
            end: CMTime(seconds: range.end, preferredTimescale: timescale)
        )
        // The rendered URL PhotoKit hands back already exists and is empty;
        // the exporter refuses to write over a file that is there.
        try? FileManager.default.removeItem(at: url)

        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: url, as: .mov)
            } catch {
                logger.error("trim export failed: \(error.localizedDescription)")
                throw VideoTrimError.exportFailed("Couldn’t save the trimmed video.")
            }
        } else {
            session.outputURL = url
            session.outputFileType = .mov
            await session.export()
            guard session.status == .completed else {
                let reason = session.error?.localizedDescription ?? "Couldn’t save the trimmed video."
                logger.error("trim export failed: \(reason)")
                throw VideoTrimError.exportFailed(reason)
            }
        }
    }

    /// Evenly spaced still frames for the trim strip, at the exact times asked
    /// for. Runs off the main actor: every frame is a decode.
    static func thumbnails(
        for asset: AVAsset,
        times: [Double],
        maximumEdge: CGFloat
    ) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        // A strip is a rough map of the clip, so any nearby frame will do —
        // and exact seeks here would decode from the previous keyframe each
        // time, which for a long clip is seconds of work for no visible gain.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var images: [CGImage] = []
        for seconds in times {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image {
                images.append(image)
            }
        }
        return images
    }
}
