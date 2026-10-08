import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// A video only in iCloud (FS-12.17b §7, AC-14): skimming never downloads.
struct VideoSkimFrameSourceTests {
    /// The library gives no local video: the source says so, and asks the
    /// loader once — not again on every pointer move.
    @Test func nilAssetFallsBackToThumbnail() async {
        let calls = SkimLoadCounter()
        let source = VideoSkimFrameSource(loadAsset: { _ in
            await calls.bump()
            return nil
        })
        #expect(await source.frame(assetID: "cloud", at: 2.3, maximumSide: 400) == .notDownloaded)
        #expect(await source.frame(assetID: "cloud", at: 2.4, maximumSide: 400) == .notDownloaded)
        #expect(await calls.value == 1)
    }

    /// Through the model: the viewer shows the cell's thumbnail and the
    /// line under the frame ends "· Not downloaded".
    @MainActor
    @Test func modelShowsThumbnailAndSaysNotDownloaded() async throws {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.skimSource = VideoSkimFrameSource(loadAsset: { _ in nil })
        let thumbnail = try #require(Self.image())
        model.skimMedia(assetID: "cloud", name: "Lake", isVideo: true, duration: 5, fraction: 0.46, thumbnail: thumbnail)
        for _ in 0..<50 where model.skim?.isNotDownloaded != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.skim?.detail == "· Lake · 0:02.3 / 0:05 · Not downloaded")
        #expect(model.skimImage === thumbnail)
    }

    private static func image() -> CGImage? {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}

private actor SkimLoadCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
