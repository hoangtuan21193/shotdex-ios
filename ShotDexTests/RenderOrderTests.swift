import CoreImage
import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-03.15 AC-6 — the render chain is one list, walked by every path that
/// renders a recipe.
struct RenderOrderTests {

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// E15. The still, a Live Photo's motion frames and the automatic-mask pass
    /// share one stage list: the order is written once, and none of the three
    /// renderers calls a stage on its own.
    @Test func stillLiveAndAutoMaskShareOnePassList() throws {
        #expect(PhotoRenderService.preMaskStages == [
            .adjustments, .color, .curve, .lensProfile, .optics, .geo, .look, .crop, .healing,
        ])

        let kit = try Self.source("ShotDexKit/Render/PhotoRenderService.swift")
        let app = try Self.source("ShotDex/Data/Sources/PhotoEditingService.swift")
        // Still render and automatic masks in the kit; Live Photo frames in the app.
        #expect(kit.components(separatedBy: "Self.applyPreMaskStages(").count - 1 == 2)
        #expect(app.components(separatedBy: "PhotoRenderService.applyPreMaskStages(").count - 1 == 1)
        // A stage called by hand anywhere else is the drift this list exists to stop.
        #expect(!app.contains("PhotoRenderService.applyColor("))
        #expect(!app.contains("PhotoRenderService.applyCurve("))
        #expect(!app.contains("PhotoRenderService.applyLook("))
        #expect(kit.components(separatedBy: "applyCurve(recipe.curve").count - 1 == 1)
    }

    /// E15. A motion frame of a Live Photo comes out of the frame renderer the
    /// way the still comes out of the editor — to 1/255 a channel — with a
    /// global edit, a crop, a healing spot and a gradient mask on it.
    @Test func livePhotoFrameMatchesStill() async throws {
        var recipe = PhotoEditRecipe()
        recipe.adjustments.exposure = 0.4
        recipe.adjustments.contrast = 0.2
        recipe.color.mixer.orange.hue = 0.3
        recipe.curve.rgb = [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.5, y: 0.55), CurvePoint(x: 1, y: 1)]
        recipe.crop.rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        recipe.healing = [
            PhotoHealingSpot(
                mode: .clone,
                center: NormalizedPoint(x: 0.3, y: 0.3),
                source: NormalizedPoint(x: 0.6, y: 0.3),
                radius: 0.04
            ),
        ]
        var gradient = PhotoMaskComponent(kind: .radialGradient)
        gradient.center = NormalizedPoint(x: 0.5, y: 0.5)
        gradient.radiusX = 0.25
        gradient.radiusY = 0.25
        var mask = PhotoMask(name: "Centre", component: gradient)
        mask.adjustments.saturation = -0.6
        recipe.masks = [mask]

        let service = PhotoRenderService()
        let info = try await service.inspectSource(at: KernelGolden.referencePhoto)
        let still = try await service.render(source: info, recipe: recipe).image

        let frame = try #require(CIImage(contentsOf: KernelGolden.referencePhoto, options: [.applyOrientationProperty: true]))
        let live = LivePhotoFrameRenderer(recipe: recipe, source: info, automaticMasks: [:])
            .render(frame)
        let liveAtOrigin = live.transformed(by: CGAffineTransform(
            translationX: -live.extent.origin.x,
            y: -live.extent.origin.y
        ))

        #expect(still.extent.size == liveAtOrigin.extent.size)
        let a = Self.pixels(still)
        let b = Self.pixels(liveAtOrigin, size: still.extent.size)
        let worst = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 255
        #expect(worst <= 1, "Live Photo frame differs from the still by \(worst)/255")
    }

    private static func pixels(_ image: CIImage, size: CGSize? = nil) -> [UInt8] {
        let size = size ?? image.extent.size
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CIContext()
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: CGRect(origin: .zero, size: size),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }
}
