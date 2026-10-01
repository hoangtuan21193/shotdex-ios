import CoreGraphics
import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15 AC-4 — a 100 MP save stays under the 1.5 GB ceiling (§5).
/// The simulator's memory is not a phone's; this is the number the
/// simulator can give, the device measurement closes it.
@MainActor
struct LargeImageRenderTests {

    static let width = 11_648
    static let height = 8_736

    /// A 100 MP JPEG of noise — detail everywhere, so no pass gets to skip
    /// work on a flat area.
    static func writePhoto(to url: URL) throws {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        try CIContext().writeJPEGRepresentation(of: noise, to: url, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Lens Blur 50, three brushed heal strokes, three masks — the heaviest
    /// recipe §5 names.
    static func heavyRecipe() -> PhotoEditRecipe {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.updateLensBlur { $0.amount = 0.5 }
        for row in 0..<3 {
            let y = 0.2 + Double(row) * 0.25
            controller.addHealingStroke(
                through: (0..<12).map { NormalizedPoint(x: 0.1 + Double($0) * 0.05, y: y) },
                radius: 0.01
            )
        }
        for option in [EditorNewMaskOption.radialGradient, .linearGradient, .luminanceRange] {
            controller.addMask(option: option)
            controller.setAdjustment(.exposure, value: 0.3)
        }
        return controller.recipe
    }

    /// AC-4. The save — full-resolution render and JPEG encode — peaks at no
    /// more than 1.5 GB above where it started.
    @Test func hundredMegapixelSaveStaysUnderCeiling() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LargeImage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("large.jpg")
        try Self.writePhoto(to: input)
        let recipe = Self.heavyRecipe()
        #expect(!recipe.lensBlur.isIdentity && recipe.healing.count == 3 && recipe.masks.count == 3)

        let renderer = PhotoRenderService()
        await renderer.setDepthEstimator(LensBlurTests.FakeEstimator())
        let source = try await renderer.inspectSource(at: input)
        #expect(source.pixelWidth * source.pixelHeight >= 100_000_000)
        _ = await FootprintSampler.waitForQuietProcess()

        let baseline = FootprintSampler.current()
        let sampler = FootprintSampler()
        sampler.start()
        let output = folder.appendingPathComponent("saved.jpg")
        let result = try await renderer.render(source: source, recipe: recipe)
        try await renderer.write(result, to: output, format: .jpeg, quality: 0.9, metadata: .all)
        let peak = sampler.stop()
        let used = peak > baseline ? peak - baseline : 0
        print("FOOTPRINT 100 MP save: \(used / 1_048_576) MB")
        #expect(used <= 1_536 * 1_048_576, "\(used / 1_048_576) MB")

        let saved = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(saved, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Self.width)
    }
}
