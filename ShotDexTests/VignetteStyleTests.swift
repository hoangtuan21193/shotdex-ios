import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15b AC-25, AC-26 — the Effects vignette's Style, and where it sits.
struct VignetteStyleTests {

    private static let size = 96

    /// Mid grey 0.5, with a 0.95 lamp in the top-left corner.
    private static func lampInTheCorner() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let value: Float = (x < 10 && y < 10) ? 0.95 : 0.5
                let index = (y * size + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private static func mean(of image: CIImage, in rect: CGRect) -> Double {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let w = Int(rect.width), h = Int(rect.height)
        var values = [Float](repeating: 0, count: w * h * 4)
        context.render(
            image,
            toBitmap: &values,
            rowBytes: w * 4 * MemoryLayout<Float>.size,
            bounds: rect,
            format: .RGBAf,
            colorSpace: nil
        )
        let greens = stride(from: 1, to: values.count, by: 4).map { Double(values[$0]) }
        return greens.reduce(0, +) / Double(greens.count)
    }

    // Core Image's origin is bottom-left: the pixel array's first rows are
    // the top of the frame, at high y.
    private static let lamp = CGRect(x: 2, y: 88, width: 6, height: 6)
    private static let greyBesideIt = CGRect(x: 14, y: 88, width: 6, height: 6)

    private static func vignetted(_ style: PhotoVignetteStyle) -> CIImage {
        var adjustments = PhotoAdjustments()
        adjustments.vignette = -0.5
        return PhotoRenderService.applyVignette(adjustments, style: style, to: lampInTheCorner())
    }

    /// AC-25. Vignette −50: Highlight Priority keeps the lamp and darkens the
    /// grey beside it; Paint Overlay darkens the lamp too.
    @Test func highlightPriorityKeepsLights() {
        let priority = Self.vignetted(.highlightPriority)
        let lamp = Self.mean(of: priority, in: Self.lamp)
        let grey = Self.mean(of: priority, in: Self.greyBesideIt)
        #expect(lamp >= 0.9, "Highlight Priority lamp \(lamp)")
        #expect(grey <= 0.5 * 0.8, "Highlight Priority grey \(grey)")

        let paint = Self.vignetted(.paintOverlay)
        let paintedLamp = Self.mean(of: paint, in: Self.lamp)
        #expect(paintedLamp <= 0.95 * 0.8, "Paint Overlay lamp \(paintedLamp)")
    }

    /// Lightroom's sign: negative darkens, positive brightens.
    @Test func negativeDarkensPositiveBrightens() {
        let input = Self.lampInTheCorner()
        var darker = PhotoAdjustments()
        darker.vignette = -0.5
        var lighter = PhotoAdjustments()
        lighter.vignette = 0.5
        for style in PhotoVignetteStyle.allCases {
            let dark = Self.mean(of: PhotoRenderService.applyVignette(darker, style: style, to: input), in: Self.greyBesideIt)
            let light = Self.mean(of: PhotoRenderService.applyVignette(lighter, style: style, to: input), in: Self.greyBesideIt)
            #expect(dark < 0.5 && light > 0.5, "\(style): −50 → \(dark), +50 → \(light)")
        }
    }

    /// Paint Overlay has no highlight protection, so Highlights goes quiet.
    @Test func paintOverlayDimsHighlights() {
        var adjustments = PhotoAdjustments()
        adjustments.vignette = -0.5
        #expect(EditorAdjustmentCatalog.isEnabled(.vignetteHighlights, in: adjustments, vignetteStyle: .highlightPriority))
        #expect(EditorAdjustmentCatalog.isEnabled(.vignetteHighlights, in: adjustments, vignetteStyle: .colorPriority))
        #expect(!EditorAdjustmentCatalog.isEnabled(.vignetteHighlights, in: adjustments, vignetteStyle: .paintOverlay))
    }
}
