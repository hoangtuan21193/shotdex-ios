import CoreGraphics
import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15e — Lens Blur, against real pixels. The test photo (§5): 512×512,
/// fine stripes across the whole frame, the top half at depth 1.0 (near) and
/// the bottom half at 0.2 (far), the map at a quarter of the resolution the
/// way a capture stores it.
struct LensBlurTests {

    static let side = 512

    /// Vertical stripes two pixels wide — detail any blur wipes out.
    static func stripes() -> CIImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        for x in stride(from: 0, to: side, by: 4) {
            context.fill(CGRect(x: x, y: 0, width: 2, height: side))
        }
        return CIImage(cgImage: context.makeImage()!)
    }

    /// Near (1.0) in the top half, far (0.2) in the bottom — Core Image's y
    /// grows upward, so "top" is the upper rows of the extent.
    static func splitDepth(near: Double = 1, far: Double = 0.2) -> CIImage {
        // Not colour-managed, like a real disparity map: 0.2 stays 0.2.
        CIImage(cgImage: splitDepthPicture(near: near, far: far), options: [.colorSpace: NSNull()])
    }

    /// The map as raw bytes: `CGColor(gray:)` is colour-matched on the way
    /// into a device-gray context, and 0.2 lands as 66/255.
    static func splitDepthPicture(near: Double = 1, far: Double = 0.2) -> CGImage {
        let mapSide = side / 4
        var bytes = [UInt8](repeating: 0, count: mapSide * mapSide)
        for row in 0..<mapSide {
            // Rows run top-down in a CGImage: the top half is near.
            let value = row < mapSide / 2 ? near : far
            for column in 0..<mapSide {
                bytes[row * mapSide + column] = UInt8((value * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: mapSide, height: mapSide, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: mapSide,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    /// The luminance of `rect`, row by row.
    static func luminance(of image: CIImage, in rect: CGRect) -> [[Double]] {
        let width = Int(rect.width), height = Int(rect.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(
            image, toBitmap: &pixels, rowBytes: width * 4, bounds: rect,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (0..<height).map { y in
            (0..<width).map { x in
                let i = (y * width + x) * 4
                return (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
            }
        }
    }

    /// Variance of the 4-neighbour Laplacian — the usual sharpness score.
    static func laplacianVariance(of image: CIImage, in rect: CGRect) -> Double {
        let rows = luminance(of: image, in: rect)
        var values: [Double] = []
        for y in 1..<(rows.count - 1) {
            for x in 1..<(rows[y].count - 1) {
                values.append(rows[y - 1][x] + rows[y + 1][x] + rows[y][x - 1] + rows[y][x + 1] - 4 * rows[y][x])
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    /// Inside each half, clear of the seam and the frame's edge.
    static let nearHalf = CGRect(x: 64, y: 320, width: 384, height: 128)
    static let farHalf = CGRect(x: 64, y: 64, width: 384, height: 128)

    static func recipe(amount: Double, far: Double, near: Double) -> PhotoLensBlurRecipe {
        var recipe = PhotoLensBlurRecipe()
        recipe.amount = amount
        recipe.focusFar = far
        recipe.focusNear = near
        return recipe
    }

    /// AC-53. Focus Range 70–100, Amount 50: the near half keeps ≥ 90% of its
    /// sharpness, the far half keeps ≤ 40%.
    @Test func focusRangeKeepsTheNearHalfSharp() {
        let input = Self.stripes()
        let output = LensBlurRenderer.apply(
            Self.recipe(amount: 0.5, far: 0.7, near: 1),
            to: input,
            depth: Self.splitDepth()
        )
        #expect(output.extent == input.extent)
        let near = Self.laplacianVariance(of: output, in: Self.nearHalf)
            / Self.laplacianVariance(of: input, in: Self.nearHalf)
        let far = Self.laplacianVariance(of: output, in: Self.farHalf)
            / Self.laplacianVariance(of: input, in: Self.farHalf)
        #expect(near >= 0.9, "near half kept \(near)")
        #expect(far <= 0.4, "far half kept \(far)")
    }

    /// Amount 0, or no depth at all, is the photo itself — not a render at
    /// radius zero.
    @Test func nothingToDoReturnsThePhoto() {
        let input = Self.stripes()
        #expect(LensBlurRenderer.apply(.identity, to: input, depth: Self.splitDepth()) === input)
        #expect(LensBlurRenderer.apply(Self.recipe(amount: 0.5, far: 0.7, near: 1), to: input, depth: nil) === input)
    }

    /// The layers partition the depth scale with no gap and no overlap, far
    /// to near, the sharp band blurring by nothing and every other step by
    /// more the farther it sits from the band.
    @Test func layersCoverTheDepthScaleFarToNear() {
        let layers = LensBlurRenderer.layers(focusFar: 0.3, focusNear: 0.6)
        #expect(layers.count == 2 * LensBlurRenderer.stepsPerSide + 1)
        #expect(layers.first?.lower == 0)
        #expect((layers.last?.upper ?? 0) > 1)
        for (a, b) in zip(layers, layers.dropFirst()) {
            #expect(abs(a.upper - b.lower) < 1e-9)
        }
        let focus = layers[LensBlurRenderer.stepsPerSide]
        #expect(focus.lower == 0.3 && focus.upper == 0.6 && focus.blur == 0)
        #expect(layers.first!.blur > layers[1].blur)
        #expect(layers.last!.blur > layers[layers.count - 2].blur)

        // Focused on the nearest part: the band and seven far steps — eight.
        #expect(LensBlurRenderer.layers(focusFar: 0.6, focusNear: 1).count == 8)
    }

    // MARK: AC-54 — bokeh shapes

    static let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// A dark 0.05 frame, everything at depth 0.2, one 3px light of 1.0 in
    /// the middle — a street lamp far behind the focus.
    static func pointLight() -> (image: CIImage, depth: CIImage) {
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let background = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1, colorSpace: linear)!)
        let light = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1, colorSpace: linear)!)
            .cropped(to: CGRect(x: side / 2 - 1, y: side / 2 - 1, width: 3, height: 3))
        let depth = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1, colorSpace: linear)!)
        return (light.composited(over: background).cropped(to: frame), depth.cropped(to: frame))
    }

    /// Mean linear luminance of the pixels whose distance from the light
    /// lies in `band` (as a share of the blur radius).
    static func meanLuminance(of image: CIImage, radius: Double, band: ClosedRange<Double>) -> Double {
        let reach = Int(ceil(radius)) + 2
        let rect = CGRect(x: side / 2 - reach, y: side / 2 - reach, width: 2 * reach + 1, height: 2 * reach + 1)
        let width = Int(rect.width), height = Int(rect.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        CIContext().render(image, toBitmap: &pixels, rowBytes: width * 16, bounds: rect, format: .RGBAf, colorSpace: linear)
        var sum = 0.0, count = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let distance = hypot(Double(x - reach), Double(y - reach)) / radius
                guard band.contains(distance) else { continue }
                let i = (y * width + x) * 4
                sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    /// AC-54. Amount 80, focus 70–100, the light at depth 0.2: Ring draws a
    /// rim at least 1.3 times as bright as its core; Circle is even (≤ 1.1).
    @Test func ringBokehHasABrightRim() {
        let scene = Self.pointLight()
        // The far layer's radius: Amount × 3.5% of the short edge × its step.
        let layer = LensBlurRenderer.layers(focusFar: 0.7, focusNear: 1).first { $0.lower <= 0.2 && 0.2 < $0.upper }!
        let radius = 0.8 * 0.035 * Double(Self.side) * layer.blur
        func ratio(_ shape: PhotoBokehShape) -> Double {
            var recipe = Self.recipe(amount: 0.8, far: 0.7, near: 1)
            recipe.bokeh = shape
            let output = LensBlurRenderer.apply(recipe, to: scene.image, depth: scene.depth)
            let rim = Self.meanLuminance(of: output, radius: radius, band: 0.7...0.9)
            let core = Self.meanLuminance(of: output, radius: radius, band: 0...0.3)
            return rim / core
        }
        let ring = ratio(.ring)
        let circle = ratio(.circle)
        #expect(ring >= 1.3, "ring rim/core \(ring)")
        #expect(circle <= 1.1 && circle >= 0.9, "circle rim/core \(circle)")
    }

    /// Every shape keeps the light's energy: the layer's average brightness
    /// stays where it was, whichever bokeh spreads it.
    @Test(arguments: PhotoBokehShape.allCases)
    func everyShapeKeepsTheLight(_ shape: PhotoBokehShape) {
        let scene = Self.pointLight()
        var recipe = Self.recipe(amount: 0.8, far: 0.7, near: 1)
        recipe.bokeh = shape
        let output = LensBlurRenderer.apply(recipe, to: scene.image, depth: scene.depth)
        let before = Self.meanLuminance(of: scene.image, radius: 12, band: 0...1)
        let after = Self.meanLuminance(of: output, radius: 12, band: 0...1)
        #expect(abs(after - before) / before < 0.15, "\(shape) moved the light's energy \(before) → \(after)")
    }

    // MARK: AC-57, AC-58 — the preview's levels

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Mean |a − b| over the frame, in 8-bit sRGB steps.
    static func meanDifference(_ a: CIImage, _ b: CIImage) -> Double {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        func pixels(_ image: CIImage) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: side * side * 4)
            CIContext().render(image, toBitmap: &out, rowBytes: side * 4, bounds: rect, format: .RGBA8, colorSpace: sRGB)
            return out
        }
        let pa = pixels(a), pb = pixels(b)
        var sum = 0.0, count = 0.0
        for i in stride(from: 0, to: pa.count, by: 4) {
            for c in 0..<3 {
                sum += abs(Double(pa[i + c]) - Double(pb[i + c]))
                count += 1
            }
        }
        return sum / count
    }

    /// AC-58. Dragging Amount 20 → 80 over 30 values builds the eight levels
    /// once and only mixes them after; at 80 the preview sits within 2/255 of
    /// the save's layered render on average.
    @Test func amountDragOnlyReblends() {
        let cache = LensBlurPreviewCache()
        let input = Self.stripes(), depth = Self.splitDepth()
        var recipe = Self.recipe(amount: 0.2, far: 0.7, near: 1)
        var last = input
        for step in 0..<30 {
            recipe.amount = 0.2 + 0.6 * Double(step) / 29
            last = cache.image(for: recipe, base: input, depth: depth, identity: "stripes", colorSpace: Self.sRGB, context: CIContext())
        }
        #expect(cache.levelBuilds == 1)
        #expect(cache.blends == 30)
        let saved = LensBlurRenderer.apply(recipe, to: input, depth: depth)
        let difference = Self.meanDifference(last, saved)
        #expect(difference <= 2, "preview vs save: \(difference)/255")
    }

    /// AC-57. With Lens Blur let go, frames for any other slider reuse the
    /// mixed picture: no level is built and nothing is mixed again. A new
    /// focus band or bokeh does rebuild.
    @Test func otherSlidersReuseTheBlendedResult() {
        let cache = LensBlurPreviewCache()
        let input = Self.stripes(), depth = Self.splitDepth()
        var recipe = Self.recipe(amount: 0.5, far: 0.7, near: 1)
        _ = cache.image(for: recipe, base: input, depth: depth, identity: "stripes", colorSpace: Self.sRGB, context: CIContext())
        for _ in 0..<30 {
            _ = cache.image(for: recipe, base: input, depth: depth, identity: "stripes", colorSpace: Self.sRGB, context: CIContext())
        }
        #expect(cache.levelBuilds == 1)
        #expect(cache.blends == 1)

        recipe.bokeh = .ring
        _ = cache.image(for: recipe, base: input, depth: depth, identity: "stripes", colorSpace: Self.sRGB, context: CIContext())
        #expect(cache.levelBuilds == 2)
    }

    // MARK: AC-56, AC-59 — estimated depth

    /// The model's stand-in: the test photo's near/far split, or an error.
    struct FakeEstimator: DepthEstimating {
        var fails = false
        struct Failure: Error {}
        func depth(of image: CGImage) throws -> CGImage {
            if fails { throw Failure() }
            return LensBlurTests.splitDepthPicture()
        }
    }

    /// The test photo saved as a JPEG with no depth, as the renderer sees it.
    static func jpegSource(in directory: URL) async throws -> PhotoRenderSourceInfo {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("stripes.jpg")
        try CIContext().writeJPEGRepresentation(of: stripes(), to: url, colorSpace: sRGB)
        var source = try await PhotoRenderService().inspectSource(at: url)
        source.persistentIdentity = "asset-stripes|original|0"
        return source
    }

    static func lensBlur(_ amount: Double) -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.lensBlur = Self.recipe(amount: amount, far: 0.7, near: 1)
        return recipe
    }

    /// AC-56. A JPEG with no depth map and Lens Blur 50: the model runs once,
    /// the depth reads as estimated; reopened — a new renderer over the same
    /// store — it runs 0 times and the far half is still blurred.
    @Test func noDepthPhotoIsEstimatedOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lensblur-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Self.jpegSource(in: directory)
        let store = GeneratedMatteStore(directory: directory.appendingPathComponent("mattes"))

        let first = PhotoRenderService()
        await first.setMatteStore(store)
        await first.setDepthEstimator(FakeEstimator())
        _ = try await first.render(source: source, recipe: Self.lensBlur(0.5))
        _ = try await first.render(source: source, recipe: Self.lensBlur(0.6))
        #expect(await first.depthEstimations == 1)
        #expect(await first.lensBlurDepth(for: source) == .estimated)

        let reopened = PhotoRenderService()
        await reopened.setMatteStore(store)
        await reopened.setDepthEstimator(FakeEstimator())
        #expect(await reopened.lensBlurDepth(for: source) == .estimated)
        let output = try await reopened.render(source: source, recipe: Self.lensBlur(0.5)).image
        #expect(await reopened.depthEstimations == 0, "reopening ran the model again")
        let input = try #require(CIImage(contentsOf: source.url))
        let far = Self.laplacianVariance(of: output, in: Self.farHalf) / Self.laplacianVariance(of: input, in: Self.farHalf)
        #expect(far <= 0.4, "far half kept \(far) — the saved depth was not used")
    }

    /// AC-59. The model fails: the photo renders as shot (± 1/255), the
    /// depth reads as failed, and nothing throws.
    @Test func estimationFailureRendersTheOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lensblur-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Self.jpegSource(in: directory)
        let renderer = PhotoRenderService()
        await renderer.setDepthEstimator(FakeEstimator(fails: true))
        let output = try await renderer.render(source: source, recipe: Self.lensBlur(0.5)).image
        let plain = try await renderer.render(source: source, recipe: .identity).image
        #expect(Self.meanDifference(output, plain) <= 1)
        #expect(await renderer.lensBlurDepth(for: source) == .failed)
        #expect(await renderer.depthEstimations == 0)
    }

    /// The bundled Depth Anything model loads and answers with a depth
    /// picture — on the simulator's CPU, so this proves the wiring, not the
    /// quality (AC-60 measures that on a device). The model is not in git
    /// (Resources/Models/README.md), so a fresh clone without it skips this
    /// one — the same way the app degrades without it.
    @Test(.enabled(if: CoreMLDepthEstimator() != nil, "DepthAnythingV2SmallF16 is not in this checkout"))
    func bundledModelAnswersWithADepthPicture() throws {
        let estimator = try #require(CoreMLDepthEstimator())
        let picture = try #require(CIContext().createCGImage(Self.stripes(), from: CGRect(x: 0, y: 0, width: Self.side, height: Self.side)))
        let depth = try estimator.depth(of: picture)
        #expect(depth.width > 100 && depth.height > 100)
    }

    // MARK: AC-55 — tap to focus

    /// AC-55. A tap on the far half (depth 0.2) puts the band at 10–30: the
    /// far half turns sharp and the near half blurs; one Undo puts the old
    /// band back. The depth under the finger is read from the estimated map.
    @MainActor @Test func tapToFocusCentresTheRange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lensblur-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Self.jpegSource(in: directory)
        let renderer = PhotoRenderService()
        await renderer.setDepthEstimator(FakeEstimator())
        _ = try await renderer.prepareLensBlurDepth(for: source)
        // The bottom half of the frame, top-down.
        let depth = try #require(await renderer.lensBlurDepthValue(
            at: NormalizedPoint(x: 0.5, y: 0.8), source: source, crop: PhotoEditRecipe.identity.crop
        ))
        #expect(abs(depth - 0.2) < 0.02, "depth under the tap: \(depth)")

        let focused = Self.recipe(amount: 0.5, far: 0.7, near: 1).focused(atDepth: depth)
        #expect(abs(focused.focusFar - 0.1) <= 0.02 && abs(focused.focusNear - 0.3) <= 0.02)
        let input = Self.stripes()
        let output = LensBlurRenderer.apply(focused, to: input, depth: Self.splitDepth())
        let far = Self.laplacianVariance(of: output, in: Self.farHalf) / Self.laplacianVariance(of: input, in: Self.farHalf)
        let near = Self.laplacianVariance(of: output, in: Self.nearHalf) / Self.laplacianVariance(of: input, in: Self.nearHalf)
        #expect(far >= 0.9, "far half kept \(far)")
        #expect(near <= 0.4, "near half kept \(near)")

        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.updateLensBlur { $0.amount = 0.5 }
        let before = controller.recipe.lensBlur
        controller.focusLensBlur(atDepth: 0.2)
        #expect(abs(controller.recipe.lensBlur.focusFar - 0.1) < 1e-9 && abs(controller.recipe.lensBlur.focusNear - 0.3) < 1e-9)
        controller.undo()
        #expect(controller.recipe.lensBlur == before)
    }

    /// The saved recipe starts on the spec's default range, 60–100.
    @Test func defaultRangeIsSixtyToAHundred() {
        #expect(PhotoLensBlurRecipe.identity.focusFar == 0.6)
        #expect(PhotoLensBlurRecipe.identity.focusNear == 1)
    }
}
