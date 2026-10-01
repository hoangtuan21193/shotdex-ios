import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.11 §6, AC-14 — the memory a full-resolution HDR save can reach.
@Suite(.serialized) struct HDRExportTests {
    /// A 24 MP RAW kept out of the repo: `build/fixtures/IMG_6310.CR3`
    /// (6000 × 4000, Canon). Tests that need it skip when it is absent.
    static let rawFixture: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/fixtures/IMG_6310.CR3")
    static var hasRawFixture: Bool { FileManager.default.fileExists(atPath: rawFixture.path) }

    /// Task 1 of the plan: the floor the RAW decoder itself costs, before any
    /// merging — one decoder and five alive together, read band by band the
    /// way a merge reads them. The numbers gate the rest of the save path.
    @Test(.enabled(if: HDRExportTests.hasRawFixture)) func rawDecoderFloor() async throws {
        _ = await FootprintSampler.waitForQuietProcess(quietSeconds: 3, timeout: .seconds(60))
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        for (decoders, band) in [(1, 256), (5, 256), (5, 128)] {
            let baseline = FootprintSampler.current()
            let sampler = FootprintSampler()
            sampler.start()
            let started = Date()
            try autoreleasepool {
                let images: [CIImage] = try (0..<decoders).map { k in
                    let raw = try #require(CIRAWFilter(imageURL: Self.rawFixture))
                    raw.boostAmount = 0
                    raw.exposure = Float(k) * 0.001 // five distinct decodes, not one cached
                    return try #require(raw.outputImage)
                }
                let width = Int(images[0].extent.width), height = Int(images[0].extent.height)
                var buffers = (0..<decoders).map { _ in [UInt16](repeating: 0, count: width * band * 4) }
                var row = 0
                while row < height {
                    let rows = min(band, height - row)
                    let rect = CGRect(x: 0, y: CGFloat(height - row - rows), width: CGFloat(width), height: CGFloat(rows))
                    for k in images.indices {
                        buffers[k].withUnsafeMutableBytes { bytes in
                            context.render(images[k], toBitmap: bytes.baseAddress!, rowBytes: width * 8,
                                           bounds: rect, format: .RGBAh, colorSpace: linear)
                        }
                    }
                    row += rows
                }
            }
            let seconds = Date().timeIntervalSince(started)
            let peak = sampler.stop()
            let deltaMB = Double(peak > baseline ? peak - baseline : 0) / 1_048_576
            print(String(format: "HDR raw floor: %d decoder(s), bands of %d rows — peak +%.0f MB over %.0f MB, %.1f s",
                         decoders, band, deltaMB, Double(baseline) / 1_048_576, seconds))
            // The save's whole budget is 700 MB (FS-01.11 §6); the decoders
            // must leave room for the merge and the tone map.
            #expect(deltaMB < 600)
        }
    }
}
