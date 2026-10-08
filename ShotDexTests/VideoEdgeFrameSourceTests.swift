import AVFoundation
import Foundation
import Testing
@testable import ShotDex

/// The frames the frame trim draws (FS-12.17 §5, §10).
struct VideoEdgeFrameSourceTests {
    /// The clip's last frame — one frame before the end of a 2 s source —
    /// decodes, no bigger than asked.
    @Test func decodesTheLastFrameAtTheSizeAsked() async throws {
        let url = try VideoExportFixtures.makeDirectory().appendingPathComponent("edge.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2, to: url)
        let source = VideoEdgeFrameSource(asset: AVURLAsset(url: url))
        let image = await source.frame(at: 2 - 1.0 / 30, maximumSide: 200)
        let frame = try #require(image)
        #expect(max(frame.width, frame.height) <= 200)
        #expect(await source.cachedCount == 1)
        _ = await source.frame(at: 2 - 1.0 / 30, maximumSide: 200)
        #expect(await source.cachedCount == 1)   // the second ask is the cache's
        await source.purge()
        #expect(await source.cachedCount == 0)
    }

    /// §10: a source that is not a file on this device is offline — it is
    /// never decoded, nothing is fetched to draw the loupe.
    @Test func streamingAssetIsOfflineWithoutDecoding() async throws {
        let stream = AVURLAsset(url: try #require(URL(string: "https://example.invalid/clip.mov")))
        #expect(!VideoEdgeFrameSource.isLocal(stream))
        let source = VideoEdgeFrameSource(asset: stream)
        #expect(await source.frame(at: 1, maximumSide: 200) == nil)
        #expect(await source.cachedCount == 0)
    }

    /// At most thirty frames are kept for an edge.
    @Test func keepsAtMostThirtyFrames() async throws {
        let url = try VideoExportFixtures.makeDirectory().appendingPathComponent("many.mp4")
        try await VideoExportFixtures.writeVideo(width: 160, height: 90, seconds: 2, to: url)
        let source = VideoEdgeFrameSource(asset: AVURLAsset(url: url))
        for index in 0..<40 {
            _ = await source.frame(at: Double(index) / 30, maximumSide: 64)
        }
        #expect(await source.cachedCount == VideoEdgeFrameSource.cacheLimit)
    }
}
