import CoreAudioTypes
import CoreGraphics
import Foundation

/// FS-24: batch video compression. The pure rules — quality levels, the
/// resolution cap, the size estimate, and when a file is skipped or the
/// batch must stop — kept apart from AVFoundation so they are unit-tested.
///
/// The encoding idea comes from HandBrake's VideoToolbox encoder
/// (`libhb/platform/macosx/encvt.c`, 1.11.2): constant quality through
/// `kVTCompressionPropertyKey_Quality` (its 1080p preset uses 0.60) rather
/// than a fixed bitrate, so a still scene costs few bits and a busy one keeps
/// its detail. The code is ShotDex's own.
enum VideoCompressionQuality: String, CaseIterable, Identifiable, Sendable {
    case maximum
    case high
    case balanced
    case smallest

    var id: String { rawValue }

    /// `AVVideoQualityKey` for the HEVC encoder, 0…1. High matches
    /// HandBrake's "H.265 Apple VideoToolbox 1080p" preset (slider 60 → 0.60).
    /// Spike 2026-11-17 on a 1080p H.264 40 Mbps clip: 88% / 58% / 38% of the
    /// source; 0.65 already came out larger than the source.
    ///
    /// Canon R6 Mark II 4K60 H.264 (2026-11-18, VMAF 4K model, intent §5):
    /// 0.70 = VMAF 99.5+ at 33% (ALL-I) / 51% (IPB) of the camera file;
    /// 0.60 = 97.6–98 at 11–15%; 0.80 came out larger than the camera file.
    var encoderQuality: Double {
        switch self {
        case .maximum: 0.70
        case .high: 0.60
        case .balanced: 0.50
        case .smallest: 0.40
        }
    }

    /// Bits per pixel per frame the estimate assumes for this level. Not a
    /// bitrate the encoder is held to — only what the "about" figure uses.
    var estimatedBitsPerPixel: Double {
        switch self {
        case .maximum: 0.15
        case .high: 0.10
        case .balanced: 0.06
        case .smallest: 0.035
        }
    }
}

/// The long-edge cap. Never enlarges; keeps the aspect ratio and orientation.
enum VideoCompressionSize: String, CaseIterable, Identifiable, Sendable {
    case original
    case uhd4K
    case fullHD

    var id: String { rawValue }

    /// Maximum long edge in pixels, nil for Original.
    var maxLongEdge: CGFloat? {
        switch self {
        case .original: nil
        case .uhd4K: 3840
        case .fullHD: 1920
        }
    }

    /// The output size for a source of `size` (display orientation). Even
    /// dimensions, because 4:2:0 HEVC needs them.
    func outputSize(for size: CGSize) -> CGSize {
        let width = abs(size.width), height = abs(size.height)
        guard width > 0, height > 0 else { return .zero }
        var scale: CGFloat = 1
        if let maxLongEdge, max(width, height) > maxLongEdge {
            scale = maxLongEdge / max(width, height)
        }
        return CGSize(width: Self.even(width * scale), height: Self.even(height * scale))
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }
}

/// What the estimate and the rules need to know about one source video.
struct VideoCompressionSource: Equatable, Sendable {
    var byteCount: Int64
    var duration: TimeInterval
    var pixelSize: CGSize
    var frameRate: Double
    var hasAudio: Bool
}

enum VideoCompressionRules {
    /// AAC bitrate for sound that has to be encoded (PCM and the like), and
    /// the figure the estimate assumes. AAC sound is copied untouched instead
    /// (`copiesAudio`): R6 II files carry AAC at 256 kbps, ~0.5% of a
    /// compressed file, so encoding it again saves nothing worth the loss.
    static let audioBitrate: Double = 256_000

    /// True when a sound track in `formatID` goes into the MP4 as it is.
    static func copiesAudio(formatID: AudioFormatID) -> Bool {
        [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(formatID)
    }

    /// An output at or above this share of the source is not worth keeping.
    static let skipRatio: Double = 0.95

    /// Headroom kept free on the volume while a file is being written.
    static let reserveBytes: Int64 = 500 * 1_000_000

    /// Estimated output bytes for one source. Never more than the source
    /// itself: a file that would grow is skipped, so it saves nothing.
    static func estimatedBytes(
        for source: VideoCompressionSource,
        quality: VideoCompressionQuality,
        size: VideoCompressionSize
    ) -> Int64 {
        let output = size.outputSize(for: source.pixelSize)
        let frameRate = source.frameRate > 0 ? min(source.frameRate, 120) : 30
        let videoBitsPerSecond = output.width * output.height * frameRate * quality.estimatedBitsPerPixel
        let audioBitsPerSecond = source.hasAudio ? audioBitrate : 0
        let bytes = Int64((videoBitsPerSecond + audioBitsPerSecond) * max(source.duration, 0) / 8)
        return min(bytes, source.byteCount)
    }

    /// Appended to the original's name, so the copy is told apart from the
    /// original in Photos, Files and on a server: `IMG_0042.MOV` is saved as
    /// `IMG_0042_compressed.mp4`.
    static let filenameSuffix = "_compressed"

    /// The name the compressed copy is saved under, nil when the original
    /// has none (PhotoKit then names it). A name that already carries the
    /// suffix keeps one, so a copy compressed again does not grow a second.
    static func outputFilename(for originalFilename: String?) -> String? {
        guard let originalFilename else { return nil }
        var base = (originalFilename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        if !base.lowercased().hasSuffix(filenameSuffix) {
            base += filenameSuffix
        }
        return base + ".mp4"
    }

    /// True when the written output is not small enough to keep.
    static func shouldSkip(outputBytes: Int64, sourceBytes: Int64) -> Bool {
        guard sourceBytes > 0 else { return true }
        return Double(outputBytes) >= Double(sourceBytes) * skipRatio
    }

    /// True when the volume has room to compress a source of `sourceBytes`
    /// it has not downloaded yet: the original's temporary copy, the output
    /// (kept under 95% of it) and Photos' own copy of the output — 2 × the
    /// source, roughly — plus a fixed reserve. `freeBytes` is the space
    /// available for work the user asked for (`DiskSpace`), which counts
    /// purgeable space the system reclaims for such a write.
    static func hasRoom(freeBytes: Int64, sourceBytes: Int64) -> Bool {
        let needed = sourceBytes * 2 + reserveBytes
        return freeBytes >= needed
    }

    /// Seconds the rest of the batch should take at the pace so far, or nil
    /// while that pace says nothing yet — the first few seconds and the first
    /// few percent are a download or a decoder warming up, and a "2 hours
    /// left" that drops to "4 min" a moment later is worse than no estimate.
    static func secondsLeft(elapsed: TimeInterval, progress: Double) -> TimeInterval? {
        guard elapsed >= 5, progress >= 0.03, progress < 1 else { return nil }
        return elapsed * (1 - progress) / progress
    }
}
