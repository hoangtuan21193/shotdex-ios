import CoreGraphics
import CoreImage
import Foundation
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
        let mapSide = side / 4
        let context = CGContext(
            data: nil, width: mapSide, height: mapSide, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(CGColor(gray: far, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: mapSide, height: mapSide / 2))
        context.setFillColor(CGColor(gray: near, alpha: 1))
        context.fill(CGRect(x: 0, y: mapSide / 2, width: mapSide, height: mapSide / 2))
        // Not colour-managed, like a real disparity map: 0.2 stays 0.2.
        return CIImage(cgImage: context.makeImage()!, options: [.colorSpace: NSNull()])
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

    /// The saved recipe starts on the spec's default range, 60–100.
    @Test func defaultRangeIsSixtyToAHundred() {
        #expect(PhotoLensBlurRecipe.identity.focusFar == 0.6)
        #expect(PhotoLensBlurRecipe.identity.focusNear == 1)
    }
}
