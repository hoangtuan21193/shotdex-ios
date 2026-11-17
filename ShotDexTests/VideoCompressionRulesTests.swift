import CoreAudioTypes
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// FS-24 AC-24.03, 04, 05, 08, 09: the pure rules of batch video compression.
struct VideoCompressionRulesTests {
    /// AC-24.03: High follows HandBrake's VideoToolbox 1080p preset (0.60).
    @Test func qualityLevelsMapToEncoderQuality() {
        #expect(VideoCompressionQuality.maximum.encoderQuality == 0.70)
        #expect(VideoCompressionQuality.high.encoderQuality == 0.60)
        #expect(VideoCompressionQuality.balanced.encoderQuality == 0.50)
        #expect(VideoCompressionQuality.smallest.encoderQuality == 0.40)
    }

    /// AC-24.04: the cap shrinks the long edge, never enlarges, keeps portrait.
    @Test(arguments: [
        (VideoCompressionSize.fullHD, CGSize(width: 3840, height: 2160), CGSize(width: 1920, height: 1080)),
        (VideoCompressionSize.fullHD, CGSize(width: 2160, height: 3840), CGSize(width: 1080, height: 1920)),
        (VideoCompressionSize.uhd4K, CGSize(width: 1280, height: 720), CGSize(width: 1280, height: 720)),
        (VideoCompressionSize.uhd4K, CGSize(width: 5760, height: 3240), CGSize(width: 3840, height: 2160)),
        (VideoCompressionSize.original, CGSize(width: 5760, height: 3240), CGSize(width: 5760, height: 3240)),
        (VideoCompressionSize.fullHD, CGSize(width: 4096, height: 2161), CGSize(width: 1920, height: 1012)),
    ])
    func resolutionCap(size: VideoCompressionSize, source: CGSize, expected: CGSize) {
        #expect(size.outputSize(for: source) == expected)
    }

    /// AC-24.05: the estimate scales with level and never exceeds the source.
    @Test func estimateOrdersByLevelAndIsBoundedBySource() {
        let source = VideoCompressionSource(
            byteCount: 600_000_000, duration: 60,
            pixelSize: CGSize(width: 3840, height: 2160), frameRate: 30, hasAudio: true
        )
        let maximum = VideoCompressionRules.estimatedBytes(for: source, quality: .maximum, size: .original)
        let high = VideoCompressionRules.estimatedBytes(for: source, quality: .high, size: .original)
        let balanced = VideoCompressionRules.estimatedBytes(for: source, quality: .balanced, size: .original)
        let smallest = VideoCompressionRules.estimatedBytes(for: source, quality: .smallest, size: .original)
        let capped = VideoCompressionRules.estimatedBytes(for: source, quality: .high, size: .fullHD)
        #expect(maximum > high && high > balanced && balanced > smallest)
        #expect(maximum <= source.byteCount)
        #expect(capped < high)
        #expect(high <= source.byteCount)

        let alreadySmall = VideoCompressionSource(
            byteCount: 1_000_000, duration: 60,
            pixelSize: CGSize(width: 3840, height: 2160), frameRate: 30, hasAudio: true
        )
        #expect(VideoCompressionRules.estimatedBytes(for: alreadySmall, quality: .high, size: .original) == 1_000_000)
    }

    /// AC-24.08: an output at 95% of the source or more is thrown away.
    @Test(arguments: [
        ("IMG_0042.MOV", "IMG_0042_compressed.mp4"),
        ("clip.final.mp4", "clip.final_compressed.mp4"),
        ("IMG_0042_compressed.mp4", "IMG_0042_compressed.mp4"),
        ("IMG_0042_Compressed.mov", "IMG_0042_Compressed.mp4"),
        ("NoExtension", "NoExtension_compressed.mp4"),
    ])
    func outputFilenameAddsSuffixOnce(original: String, expected: String) {
        #expect(VideoCompressionRules.outputFilename(for: original) == expected)
    }

    @Test func outputFilenameNeedsAName() {
        #expect(VideoCompressionRules.outputFilename(for: nil) == nil)
        #expect(VideoCompressionRules.outputFilename(for: "") == nil)
    }

    @Test func aacSoundIsCopiedOtherSoundEncoded() {
        #expect(VideoCompressionRules.copiesAudio(formatID: kAudioFormatMPEG4AAC))
        #expect(VideoCompressionRules.copiesAudio(formatID: kAudioFormatMPEG4AAC_HE))
        #expect(!VideoCompressionRules.copiesAudio(formatID: kAudioFormatLinearPCM))
        #expect(!VideoCompressionRules.copiesAudio(formatID: kAudioFormatAppleLossless))
    }

    @Test func skipRule() {
        #expect(VideoCompressionRules.shouldSkip(outputBytes: 95, sourceBytes: 100))
        #expect(VideoCompressionRules.shouldSkip(outputBytes: 120, sourceBytes: 100))
        #expect(!VideoCompressionRules.shouldSkip(outputBytes: 94, sourceBytes: 100))
        #expect(VideoCompressionRules.shouldSkip(outputBytes: 0, sourceBytes: 0))
    }

    /// AC-24.09: room needed is 2 × the source plus a 500 MB reserve.
    @Test func freeSpaceRule() {
        let source: Int64 = 1_000_000_000
        #expect(VideoCompressionRules.hasRoom(freeBytes: 2_500_000_000, sourceBytes: source))
        #expect(!VideoCompressionRules.hasRoom(freeBytes: 2_499_999_999, sourceBytes: source))
    }
}
