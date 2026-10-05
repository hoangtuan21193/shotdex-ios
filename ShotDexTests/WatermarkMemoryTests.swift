import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-05.04 AC-14, the part a simulator can measure: stamping a 48MP photo
/// costs at most 40 MB more than writing it unstamped — the stamp rasterizes
/// its box, never a bitmap the size of the photo. The device number is
/// measured on an iPhone 17 (`/verify`).
@Suite(.serialized)
struct WatermarkMemoryTests {
    static let width = 8064
    static let height = 6048

    /// The peak footprint above the baseline while one write runs.
    static func peakOfWrite(_ result: PhotoRenderResult, renderer: PhotoRenderService, to url: URL) async throws -> UInt64 {
        try? FileManager.default.removeItem(at: url)
        let baseline = FootprintSampler.current()
        let sampler = FootprintSampler()
        sampler.start()
        try await renderer.write(result, to: url, format: .jpeg, quality: 0.8, metadata: .all)
        let peak = sampler.stop()
        return peak > baseline ? peak - baseline : 0
    }

    @Test(arguments: [0.04, 0.25])
    func stampAt48MPAddsUnder40MB(size: Double) async throws {
        if let waited = await FootprintSampler.waitForQuietProcess() {
            print("FOOTPRINT watermark: process quiet after \(waited)")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkMemory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = OverlayImageStore()
        let logo = try WatermarkFixture.storeLogo(in: store)
        defer {
            store.remove(id: logo)
            try? FileManager.default.removeItem(at: folder)
        }
        let source = try WatermarkFixture.jpeg(width: Self.width, height: Self.height, in: folder)
        let renderer = PhotoRenderService()
        let info = try await renderer.inspectSource(at: source)
        let rendered = try await renderer.render(source: info, recipe: .identity)
        let original = await renderer.resize(rendered, preset: .original, cropAnchor: .center)
        var placement = WatermarkFixture.placementW
        placement.size = size
        let stamp = WatermarkStamp(preset: WatermarkFixture.credit(logo: logo), placement: placement)
            .resolved(with: OverlayTokenValues(camera: "ILCE-7M4"))
        let stamped = await renderer.applyingWatermark(stamp, to: original)
        let out = folder.appendingPathComponent("out.jpg")

        // Warm-up: kernels and encoder pipelines are built once.
        _ = try await Self.peakOfWrite(stamped, renderer: renderer, to: out)
        var plain = UInt64.max
        var withStamp = UInt64.max
        for _ in 0..<2 {
            plain = min(plain, try await Self.peakOfWrite(original, renderer: renderer, to: out))
            withStamp = min(withStamp, try await Self.peakOfWrite(stamped, renderer: renderer, to: out))
        }
        let frame = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: CGSize(width: Self.width, height: Self.height)))
        let extra = withStamp > plain ? withStamp - plain : 0
        print("FOOTPRINT watermark size \(size): box \(Int(frame.box.width))×\(Int(frame.box.height)), plain \(plain / 1_048_576) MB, stamped \(withStamp / 1_048_576) MB, extra \(extra / 1_048_576) MB")
        #expect(extra <= 40 * 1_048_576, "size \(size): +\(extra / 1_048_576) MB")
    }

    /// The bands the write draws a large stamp in leave no seam, a shadow
    /// included: the file's pixels agree with the stamp composited whole.
    @Test func bandsLeaveNoSeam() async throws {
        var preset = WatermarkFixture.credit(logo: nil)
        preset.layers[0].shadowOpacity = 0.8
        preset.layers[0].shadowRadius = 0.3
        preset.layers[0].shadowOffsetY = 0.2
        var placement = WatermarkFixture.placementW
        placement.size = 0.25
        let stamp = WatermarkStamp(preset: preset, placement: placement)
            .resolved(with: OverlayTokenValues(camera: "ILCE-7M4"))
        let image = CIImage(cgImage: WatermarkFixture.image(width: 6000, height: 4000))
        let result = PhotoRenderResult(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, properties: [:])
        let renderer = PhotoRenderService()
        let frame = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: CGSize(width: 6000, height: 4000)))
        // More than one band at this size: the test means something.
        #expect(Int(frame.box.width) * Int(frame.box.height) * 4 > PhotoRenderService.largestWatermarkBandBytes)
        let banded = WatermarkFixture.pixels(of: try await renderer.encodablePixels(renderer.applyingWatermark(stamp, to: result)))
        let whole = WatermarkFixture.pixels(of: PhotoRenderService.applyWatermark(stamp, to: image))
        var worst = 0
        for index in 0..<banded.data.count where index % 4 != 3 {
            worst = max(worst, abs(Int(banded.data[index]) - Int(whole.data[index])))
        }
        #expect(worst <= 3, "largest channel difference \(worst)")
    }
}
