import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
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

    /// A flat mid-grey PNG on disk, for a full render.
    private static func flatGreyFile(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vignette-crop-\(UUID().uuidString).png")
        let bytes = [UInt8](repeating: 128, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// AC-26. With the crop keeping the left half, the vignette is centred on
    /// the cropped frame: the brightest column sits in its middle, not at the
    /// right edge where the uncropped centre would be.
    @Test func vignetteFollowsTheCrop() async throws {
        let url = try Self.flatGreyFile(width: 400, height: 200)
        defer { try? FileManager.default.removeItem(at: url) }
        var recipe = PhotoEditRecipe()
        recipe.adjustments.vignette = -0.5
        recipe.crop.rect = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)

        let service = PhotoRenderService()
        let info = try await service.inspectSource(at: url)
        let output = try await service.render(source: info, recipe: recipe).image
        let extent = output.extent

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let width = Int(extent.width), height = Int(extent.height)
        var values = [Float](repeating: 0, count: width * height * 4)
        context.render(
            output,
            toBitmap: &values,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil
        )
        let middleRow = height / 2
        let row = (0..<width).map { Double(values[(middleRow * width + $0) * 4 + 1]) }
        let peak = row.max() ?? 0
        let brightest = row.indices.filter { row[$0] >= peak - 0.002 }
        let centre = Double(brightest.reduce(0, +)) / Double(brightest.count)
        let offset = abs(centre + 0.5 - Double(width) / 2) / Double(min(width, height))
        #expect(offset <= 0.02, "brightest column at \(centre) of \(width) — \(offset) of the short side off centre")
    }

    /// AC-26. Grain lands after the vignette: it is as strong in a darkened
    /// corner as in the middle. Laid under the vignette, the corner's grain
    /// would be scaled down with the corner.
    @Test func grainRunsAfterTheVignette() {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        var adjustments = PhotoAdjustments()
        adjustments.vignette = -1
        adjustments.grain = 0.8
        let output = PhotoRenderService.applyEffects(adjustments, to: input)

        func spread(_ rect: CGRect) -> Double {
            let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
            let w = Int(rect.width), h = Int(rect.height)
            var values = [Float](repeating: 0, count: w * h * 4)
            context.render(output, toBitmap: &values, rowBytes: w * 4 * MemoryLayout<Float>.size,
                           bounds: rect, format: .RGBAf, colorSpace: nil)
            let greens = stride(from: 1, to: values.count, by: 4).map { Double(values[$0]) }
            let mean = greens.reduce(0, +) / Double(greens.count)
            return (greens.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(greens.count)).squareRoot()
        }
        let corner = spread(CGRect(x: 0, y: 0, width: 12, height: 12))
        let middle = spread(CGRect(x: 42, y: 42, width: 12, height: 12))
        #expect(corner >= middle * 0.7, "grain σ corner \(corner) against middle \(middle)")
        #expect(PhotoRenderService.postMaskPasses.last == .effects)
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
