import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDex

/// Video Settings' arithmetic (FS-12.10 §5, FS-12.01 §9).
struct VideoOutputSpecTests {
    /// AC-4: the 18 frame sizes of §5's table — short edge by resolution,
    /// long edge by ratio, capped at 3840 — every edge even.
    @Test func everyRatioAndResolution() {
        let table: [VideoAspect: [VideoResolution: CGSize]] = [
            .r16x9: [.p720: .init(width: 1280, height: 720), .p1080: .init(width: 1920, height: 1080), .uhd4K: .init(width: 3840, height: 2160)],
            .r9x16: [.p720: .init(width: 720, height: 1280), .p1080: .init(width: 1080, height: 1920), .uhd4K: .init(width: 2160, height: 3840)],
            .r1x1: [.p720: .init(width: 720, height: 720), .p1080: .init(width: 1080, height: 1080), .uhd4K: .init(width: 2160, height: 2160)],
            .r4x5: [.p720: .init(width: 720, height: 900), .p1080: .init(width: 1080, height: 1350), .uhd4K: .init(width: 2160, height: 2700)],
            .r4x3: [.p720: .init(width: 960, height: 720), .p1080: .init(width: 1440, height: 1080), .uhd4K: .init(width: 2880, height: 2160)],
            .r21x9: [.p720: .init(width: 1680, height: 720), .p1080: .init(width: 2520, height: 1080), .uhd4K: .init(width: 3840, height: 1646)],
        ]
        #expect(table.count == VideoAspect.allCases.count)
        for aspect in VideoAspect.allCases {
            for resolution in VideoResolution.allCases {
                let size = VideoOutputSpec.frameSize(aspect: aspect, resolution: resolution)
                #expect(size == table[aspect]?[resolution], "\(aspect.displayName) \(resolution.displayName)")
                #expect(size.width.truncatingRemainder(dividingBy: 2) == 0 && size.height.truncatingRemainder(dividingBy: 2) == 0)
            }
        }
    }

    /// AC-15: a new project's ratio is the one nearest its first clip — a
    /// portrait video is 9:16, a 4032×3024 photo 4:3, a square 1:1.
    @Test func defaultAspectIsNearestToFirstClip() {
        #expect(VideoAspect.nearest(to: 1080.0 / 1920) == .r9x16)
        #expect(VideoAspect.nearest(to: 4032.0 / 3024) == .r4x3)
        #expect(VideoAspect.nearest(to: 1) == .r1x1)
        #expect(VideoAspect.nearest(to: 1920.0 / 1080) == .r16x9)
        #expect(VideoAspect.nearest(to: 2.4) == .r21x9)
        #expect(VideoAspect.nearest(to: 3.0 / 4) == .r4x5)
        #expect(VideoAspect.nearest(to: .nan) == .r16x9)
        let fresh = VideoProjectRecipe(clips: [])
        #expect(fresh.framing == .fit && fresh.background.kind == .colour && fresh.background.colour == .black)
        #expect(fresh.resolution == .p1080 && fresh.frameRate == .fps30 && fresh.codec == .h264)
    }
}

extension VideoOutputSpecTests {
    /// AC-7: 9:16 · 1080p · 30 · H.264 over 24.0 s is "~30 MB"; HEVC makes
    /// it "~18 MB".
    @Test func hevcDropsThirtyToEighteen() {
        var recipe = VideoProjectRecipe(clips: [])
        recipe.aspect = .r9x16
        #expect(VideoExportEstimate.label(VideoExportEstimate.bytes(for: recipe, duration: 24)) == "~30 MB")
        recipe.codec = .hevc
        #expect(VideoExportEstimate.label(VideoExportEstimate.bytes(for: recipe, duration: 24)) == "~18 MB")
    }

    /// From 1000 MB the label is in gigabytes, one decimal.
    @Test func gigabyteFormatting() {
        #expect(VideoExportEstimate.label(999_400_000) == "~999 MB")
        #expect(VideoExportEstimate.label(1_200_000_000) == "~1.2 GB")
        var recipe = VideoProjectRecipe(clips: [])
        recipe.resolution = .uhd4K
        recipe.frameRate = .fps60
        // 3840×2160×60×0.16 ≈ 79.6 Mbps: two minutes is about 1.2 GB.
        #expect(VideoExportEstimate.label(VideoExportEstimate.bytes(for: recipe, duration: 120)) == "~1.2 GB")
    }

    /// FS-12.01 §9, plan T-5: the writer asks the encoder for the bitrate
    /// the estimate counted — one number, so the Output line and the file
    /// cannot drift apart. 1080p30 H.264 is 9 953 280 bps.
    @Test func writerAndEstimateShareOneBitrate() throws {
        var recipe = VideoProjectRecipe(clips: [])
        recipe.codec = .hevc
        recipe.frameRate = .fps60
        let encoding = VideoEncodingSettings.make(for: recipe)
        #expect(encoding.bitrate == VideoExportEstimate.videoBitrate(frame: recipe.canvasSize(), frameRate: .fps60, codec: .hevc))
        let settings = VideoExportWriter.videoSettings(encoding)
        let compression = try #require(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect(compression[AVVideoAverageBitRateKey] as? Int == encoding.bitrate)
        #expect(settings[AVVideoCodecKey] as? AVVideoCodecType == .hevc)
        #expect(VideoExportEstimate.videoBitrate(frame: CGSize(width: 1920, height: 1080), frameRate: .fps30, codec: .h264) == 9_953_280)
    }
}

extension VideoOutputSpecTests {
    /// AC-5: the sample — two 4032×3024 photos, three 1920×1080 videos —
    /// shuts 4K: "3 of your 5 clips are 1080p."
    @Test func threeOfFiveAre1080p() {
        let verdict = VideoResolutionGate.verdict(shortEdges: [3024, 1080, 1080, 3024, 1080])
        #expect(verdict == .blocked(short: 3, total: 5, sharedClass: .p1080))
        #expect(VideoStudioCopy.fourKReason(verdict) == "4K needs 4K clips — 3 of your 5 clips are 1080p.")
    }

    /// Short clips of different classes are "smaller than 4K".
    @Test func mixedSizesSaySmallerThan4K() {
        let verdict = VideoResolutionGate.verdict(shortEdges: [3024, 720, 1080])
        #expect(verdict == .blocked(short: 2, total: 3, sharedClass: nil))
        #expect(VideoStudioCopy.fourKReason(verdict) == "4K needs 4K clips — 2 of your 3 clips are smaller than 4K.")
        #expect(VideoResolutionGate.verdict(shortEdges: [480]) == .blocked(short: 1, total: 1, sharedClass: nil))
        #expect(VideoStudioCopy.fourKReason(.blocked(short: 1, total: 4, sharedClass: nil)) == "4K needs 4K clips — 1 of your 4 clips is smaller than 4K.")
    }

    /// AC-5 (unlock): the three videos replaced by 3840×2160 ones opens 4K;
    /// a clip still loading neither opens nor shuts it.
    @Test func allUHDUnlocks4K() {
        #expect(VideoResolutionGate.verdict(shortEdges: [3024, 2160, 2160, 3024, 2160]) == .allowed)
        #expect(VideoResolutionGate.verdict(shortEdges: [2160, nil]) == .allowed)
        #expect(VideoStudioCopy.fourKReason(.allowed) == nil)
    }

    /// A freeze frame counts by the video it came from, not by the frame
    /// the session lifted at canvas size.
    @Test @MainActor func freezeUsesSourceVideoSize() {
        var freeze = VideoClip(assetID: "v", kind: .freeze)
        freeze.photoDuration = 2
        let model = VideoStudioModelFixture.model(clips: [freeze])
        defer { model.close() }
        model.sources[freeze.id] = .freeze(image: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                                           pixelSize: CGSize(width: 1920, height: 1080), videoSize: CGSize(width: 3840, height: 2160))
        #expect(model.clipSourceShortEdges == [2160])
        #expect(model.fourKVerdict == .allowed)
    }
}

extension VideoOutputSpecTests {
    /// FS-12.10b AC-7: 40 MB free and ~30 MB to write — not enough for
    /// the file and its copy in Photos; "about 60 MB needed".
    @Test func spaceCheckNeedsTwiceTheEstimate() {
        #expect(ExportSpaceCheck.shortfall(estimate: 30_000_000, available: 40_000_000) == 60_000_000)
        #expect(ExportSpaceCheck.shortfall(estimate: 30_000_000, available: 60_000_000) == nil)
        #expect(ExportSpaceCheck.shortfall(estimate: 30_000_000, available: nil) == nil)
        #expect(VideoStudioCopy.notEnoughSpace("60 MB") == "Not enough space to export — about 60 MB needed. Free up space, then try again.")
    }
}
