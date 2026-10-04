import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// The stamp through the kit's renderer, the way Resize runs it
/// (FS-05.04 AC-1): render → resize → stamp → write.
@Suite(.serialized)
struct WatermarkRenderTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatermarkRenderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func stamp(logo: UUID?) -> WatermarkStamp {
        WatermarkStamp(preset: WatermarkFixture.credit(logo: logo), placement: WatermarkFixture.placementW)
            .resolved(with: OverlayTokenValues(camera: "ILCE-7M4"))
    }

    /// AC-1: photo A, Resize 2048px, configuration W. The box is where the
    /// spec says; outside it the render before encoding is the unstamped one
    /// to the bit, and the JPEG matches outside the box grown to its 16px
    /// blocks.
    @Test func outsideTheBoxIsUntouched() async throws {
        let store = OverlayImageStore()
        let logo = try WatermarkFixture.storeLogo(in: store)
        defer {
            store.remove(id: logo)
            try? FileManager.default.removeItem(at: folder)
        }
        let source = try WatermarkFixture.jpeg(width: 6000, height: 4000, in: folder)
        let renderer = PhotoRenderService()
        let info = try await renderer.inspectSource(at: source)
        let rendered = try await renderer.render(source: info, recipe: .identity)
        let preset = ResizePreset(name: "2048", kind: .longEdge, longEdge: 2048, quality: 0.8, format: .jpeg)
        let plain = await renderer.resize(rendered, preset: preset, cropAnchor: .center)
        let stamp = stamp(logo: logo)
        let stamped = await renderer.applyingWatermark(stamp, to: plain)

        #expect(plain.image.extent.size == CGSize(width: 2048, height: 1365))
        let frame = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: plain.image.extent.size))
        #expect(abs(frame.box.maxX - 2007) <= 1)
        #expect(abs(frame.box.maxY - 1324) <= 1)
        #expect(abs(frame.box.height - 55) <= 1)

        let box = frame.box.integral
        // What `write` hands the encoder, both ways.
        let before = WatermarkFixture.pixels(of: try await renderer.encodablePixels(plain))
        let after = WatermarkFixture.pixels(of: try await renderer.encodablePixels(stamped))
        let renderDiff = WatermarkFixture.differences(
            before.data, after.data, width: before.width, height: before.height, excluding: box
        )
        #expect(renderDiff.outside == 0, "render: \(renderDiff) box \(box)")
        #expect(renderDiff.inside > 500)

        let plainURL = folder.appendingPathComponent("plain.jpg")
        let stampedURL = folder.appendingPathComponent("stamped.jpg")
        try await renderer.write(plain, to: plainURL, format: .jpeg, quality: 0.8, metadata: .all)
        try await renderer.write(stamped, to: stampedURL, format: .jpeg, quality: 0.8, metadata: .all)
        let plainFile = try #require(WatermarkFixture.pixels(of: plainURL))
        let stampedFile = try #require(WatermarkFixture.pixels(of: stampedURL))
        #expect(plainFile.width == 2048 && plainFile.height == 1365)
        let fileDiff = WatermarkFixture.differences(
            plainFile.data, stampedFile.data, width: plainFile.width, height: plainFile.height,
            excluding: WatermarkFixture.blockAligned(box)
        )
        #expect(fileDiff.outside == 0, "file: \(fileDiff)")
    }

    /// The bitmap is the block's box, never the photo (FS-05.04 §6).
    @Test func onlyTheBoxIsRasterized() throws {
        let store = OverlayImageStore()
        let logo = try WatermarkFixture.storeLogo(in: store)
        defer { store.remove(id: logo) }
        let size = CGSize(width: 6000, height: 4000)
        let stamp = stamp(logo: logo)
        let frame = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: size))
        let raster = try #require(PhotoRenderService.watermarkRaster(stamp, imageSize: size))
        #expect(raster.rect == frame.box.integral)
        #expect(raster.image.width == Int(raster.rect.width))
        #expect(raster.image.height == Int(raster.rect.height))
        #expect(raster.image.width * raster.image.height < 6000 * 4000 / 20)
    }

    /// A logo whose file is gone takes no room, and a stamp with nothing left
    /// to draw leaves the photo as it was.
    @Test func nothingToDrawLeavesThePhoto() async throws {
        var stamp = WatermarkStamp(preset: WatermarkFixture.credit(logo: nil), placement: WatermarkFixture.placementW)
        stamp.layers[0].text = "{lens}"
        let resolved = stamp.resolved(with: OverlayTokenValues(camera: "X-T5"))
        #expect(!resolved.hasVisibleLayers)
        let image = CIImage(cgImage: WatermarkFixture.image(width: 300, height: 200))
        let result = PhotoRenderResult(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, properties: [:])
        let out = await PhotoRenderService().applyingWatermark(resolved, to: result)
        #expect(out.image === result.image)
    }
}
