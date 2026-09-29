import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct LookExportCubeTests {
    /// FS-03.14 AC-c4. Mono + Clarity +40 bakes to a 33³ table; applied to a
    /// test frame it lands within 1/255 on average of ShotDex's own Mono, and
    /// Clarity is the one line the sheet names.
    @Test func bakesColourOnly() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.filter = .mono
        recipe.adjustments.clarity = 0.4
        let context = CIContext()
        let output = try #require(LookCubeBaker.bake(LookPreset(name: "Mono Clarity", recipe: recipe), context: context))
        #expect(output.lostSettings == ["Clarity"])
        #expect(LookExport.lostLine(output.lostSettings, into: "a .cube") == "Clarity doesn't carry into a .cube")

        let lut = try CubeLUTParser.parse(output.text)
        #expect(lut.dimension == 33)

        let frame = Self.testFrame()
        let viaCube = PhotoRenderService.applyLUT(lut, intensity: 1, to: frame)
        let direct = PhotoRenderService.applyFilter(.mono, intensity: 1, to: frame)
        let a = Self.pixels(viaCube, context: context)
        let b = Self.pixels(direct, context: context)
        let meanError = zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Float(a.count)
        #expect(meanError <= 1.0 / 255, "mean error \(meanError * 255)/255")
    }

    /// An imported look's LUT bakes in, and a look with nothing on is the
    /// identity table.
    @Test func identityLookIsTheIdentityTable() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.contrast = 0
        let output = try #require(LookCubeBaker.bake(LookPreset(name: "Plain", recipe: recipe)))
        let lut = try CubeLUTParser.parse(output.text)
        let size = lut.dimension
        var worst: Float = 0
        for index in 0..<(size * size * size) {
            let expected = [index % size, index / size % size, index / (size * size)].map { Float($0) / Float(size - 1) }
            for channel in 0..<3 {
                worst = max(worst, abs(lut.table[index * 4 + channel] - expected[channel]))
            }
        }
        #expect(worst < 0.5 / 255)
        #expect(output.lostSettings.isEmpty)
    }

    /// 64×64 of colours spread over the cube, not a flat card.
    private static func testFrame() -> CIImage {
        let side = 64
        var values = [Float](repeating: 1, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                values[i] = Float(x) / Float(side - 1)
                values[i + 1] = Float(y) / Float(side - 1)
                values[i + 2] = Float((x * 7 + y * 13) % side) / Float(side - 1)
            }
        }
        return CIImage(
            bitmapData: values.withUnsafeBytes { Data($0) },
            bytesPerRow: side * 16,
            size: CGSize(width: side, height: side),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }

    private static func pixels(_ image: CIImage, context: CIContext) -> [Float] {
        let side = 64
        var out = [Float](repeating: 0, count: side * side * 4)
        out.withUnsafeMutableBytes {
            context.render(
                image,
                toBitmap: $0.baseAddress!,
                rowBytes: side * 16,
                bounds: CGRect(x: 0, y: 0, width: side, height: side),
                format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        }
        return stride(from: 0, to: out.count, by: 4).flatMap { out[$0..<$0 + 3] }
    }
}
