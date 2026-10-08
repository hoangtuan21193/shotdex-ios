@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Photos

/// The frames a pointer skims over a library video (FS-12.17b §6–7): the
/// source's frame under the pointer, decoded to no more than the viewer
/// shows. **Never over the network** — a video only in iCloud answers
/// `.notDownloaded`, and the viewer shows the cell's thumbnail instead;
/// skimming is not a reason to download anything.
///
/// Decoding tolerance is half a frame either side (1/60 s): faster than
/// exact, and never more than a frame off.
actor VideoSkimFrameSource {
    enum Frame: Equatable {
        case image(CGImage)
        /// In iCloud only, not on this device.
        case notDownloaded
        /// On the device, but the frame could not be read.
        case unavailable

        static func == (lhs: Frame, rhs: Frame) -> Bool {
            switch (lhs, rhs) {
            case (.image(let a), .image(let b)): a === b
            case (.notDownloaded, .notDownloaded), (.unavailable, .unavailable): true
            default: false
            }
        }
    }

    /// The source of a library video, or nil when it is not on the device.
    typealias AssetLoader = @Sendable (String) async -> AVAsset?

    static let tolerance = CMTime(value: 1, timescale: 60)

    private let loadAsset: AssetLoader
    /// One generator per source while it is skimmed; another source
    /// replaces it.
    private var current: (id: String, generator: AVAssetImageGenerator?)?

    init(loadAsset: @escaping AssetLoader = VideoSkimFrameSource.localLibraryAsset) {
        self.loadAsset = loadAsset
    }

    func frame(assetID: String, at seconds: Double, maximumSide: CGFloat) async -> Frame {
        let generator: AVAssetImageGenerator
        if let current, current.id == assetID {
            guard let existing = current.generator else { return .notDownloaded }
            generator = existing
        } else {
            guard let asset = await loadAsset(assetID), VideoEdgeFrameSource.isLocal(asset) else {
                current = (assetID, nil)
                return .notDownloaded
            }
            let made = AVAssetImageGenerator(asset: asset)
            made.appliesPreferredTrackTransform = true
            made.requestedTimeToleranceBefore = Self.tolerance
            made.requestedTimeToleranceAfter = Self.tolerance
            current = (assetID, made)
            generator = made
        }
        generator.maximumSize = CGSize(width: maximumSide, height: maximumSide)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return .unavailable }
        return .image(image)
    }

    /// Done skimming: the generator goes.
    func reset() {
        current = nil
    }

    /// PhotoKit's video for `assetID`, with the network off: nil for a
    /// video that is only in iCloud.
    static let localLibraryAsset: AssetLoader = { assetID in
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
              asset.mediaType == .video
        else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.version = .current
        options.deliveryMode = .fastFormat
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                nonisolated(unsafe) let result = avAsset
                continuation.resume(returning: result)
            }
        }
    }
}
