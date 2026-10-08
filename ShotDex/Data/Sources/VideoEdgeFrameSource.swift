@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// Decodes the frames around a clip's edge for the frame trim (FS-12.17 §5,
/// §10): the loupe's ten and the one the viewer shows — exact frames, no
/// tolerance, at no more than the size they are drawn.
///
/// Rules it keeps:
/// - **Local files only.** A source that is not a file on this device (an
///   iCloud stream) is reported offline and never decoded: the loupe is not
///   a reason to download anything.
/// - **At most 30 frames per edge.** The cache drops the oldest beyond that;
///   `purge()` drops everything (a memory warning, the trim ending).
/// - One generator per source, reused between steps: each ±1 adds one new
///   frame to decode, the other nine are cached.
actor VideoEdgeFrameSource {
    /// How many frames the cache keeps.
    static let cacheLimit = 30

    private let asset: AVAsset
    private let generator: AVAssetImageGenerator
    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []

    private struct Key: Hashable {
        let millisecond: Int
        let maximumSide: Int
    }

    /// Whether `asset` can be read without the network.
    nonisolated static func isLocal(_ asset: AVAsset) -> Bool {
        (asset as? AVURLAsset)?.url.isFileURL ?? false
    }

    init(asset: AVAsset) {
        self.asset = asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.generator = generator
    }

    /// The frame at `seconds` of the source, its longer side at most
    /// `maximumSide` pixels. Nil when the source is not local or the frame
    /// cannot be read.
    func frame(at seconds: Double, maximumSide: CGFloat) async -> CGImage? {
        guard Self.isLocal(asset), seconds.isFinite else { return nil }
        let key = Key(millisecond: Int((seconds * 1000).rounded()), maximumSide: Int(maximumSide.rounded()))
        if let cached = cache[key] { return cached }
        generator.maximumSize = CGSize(width: maximumSide, height: maximumSide)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }
        store(image, for: key)
        return image
    }

    /// Drops every decoded frame.
    func purge() {
        cache.removeAll()
        order.removeAll()
    }

    var cachedCount: Int { cache.count }

    private func store(_ image: CGImage, for key: Key) {
        if cache[key] == nil { order.append(key) }
        cache[key] = image
        while order.count > Self.cacheLimit {
            cache.removeValue(forKey: order.removeFirst())
        }
    }
}
