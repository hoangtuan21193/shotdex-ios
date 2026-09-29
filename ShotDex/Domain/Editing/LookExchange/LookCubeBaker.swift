import CoreImage
import Foundation
import ShotDexKit
import UniformTypeIdentifiers

/// A look as a 33³ `.cube` (FS-03.14c §1): an sRGB lattice run through the
/// look's per-pixel stages — tone, white balance, colour, curve, film look
/// or LUT. What looks at neighbouring pixels cannot live in a table and is
/// named in the export sheet's one line instead.
enum LookCubeBaker {
    static let dimension = 33

    struct Output {
        var text: String
        /// "Clarity", "Grain" — settings the table cannot carry.
        var lostSettings: [String]
    }

    /// The part of `recipe` a LUT can hold. Everything else starts from
    /// the defaults, Lens Correction off.
    static func colourOnly(_ recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        var baked = PhotoEditRecipe.identity
        let source = recipe.adjustments
        var adjustments = PhotoAdjustments()
        adjustments.lensCorrection = 0
        let carried: [WritableKeyPath<PhotoAdjustments, Double>] = [
            \.exposure, \.highlights, \.shadows, \.whites, \.contrast, \.brightness, \.blackPoint,
            \.saturation, \.vibrance, \.warmth, \.tint, \.blackAndWhite,
        ]
        for key in carried { adjustments[keyPath: key] = source[keyPath: key] }
        baked.adjustments = adjustments
        baked.color = recipe.color
        baked.curve = recipe.curve
        baked.filter = recipe.filter
        baked.filterIntensity = recipe.filterIntensity
        baked.lutID = recipe.lutID
        return baked
    }

    /// Neighbourhood settings the look has on, in panel order.
    static func lostSettings(_ recipe: PhotoEditRecipe) -> [String] {
        let a = recipe.adjustments
        let checks: [(String, Bool)] = [
            ("Brilliance", a.brilliance != 0),
            ("Texture", a.texture != 0),
            ("Clarity", a.clarity != 0),
            ("Dehaze", a.dehaze != 0),
            ("Sharpening", a.sharpness != 0 || a.definition != 0),
            ("Noise Reduction", a.noiseReduction != 0 || a.colorNoiseReduction != 0),
            ("Vignette", a.vignette != 0),
            ("Grain", a.grain != 0),
        ]
        return checks.filter(\.1).map(\.0)
    }

    static func bake(_ preset: LookPreset, context: CIContext = CIContext()) -> Output? {
        let size = dimension
        let count = size * size * size
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // One pixel per lattice point, red fastest — the order a .cube lists them.
        var lattice = [Float](repeating: 1, count: count * 4)
        let step = Float(size - 1)
        for index in 0..<count {
            lattice[index * 4] = Float(index % size) / step
            lattice[index * 4 + 1] = Float(index / size % size) / step
            lattice[index * 4 + 2] = Float(index / (size * size)) / step
        }
        let width = size * size
        let bytesPerRow = width * 4 * MemoryLayout<Float>.size
        let input = CIImage(
            bitmapData: lattice.withUnsafeBytes { Data($0) },
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: size),
            format: .RGBAf,
            colorSpace: sRGB
        )
        let source = PhotoRenderSourceInfo(
            url: URL(fileURLWithPath: "/dev/null"),
            type: .png,
            pixelWidth: width,
            pixelHeight: size,
            orientation: .up,
            isRAW: false,
            properties: [:]
        )
        let output = PhotoRenderService.applyPreMaskStages(
            of: colourOnly(preset.recipe),
            source: source,
            appliesExposure: true,
            to: input
        ).cropped(to: input.extent)

        var baked = [Float](repeating: 0, count: count * 4)
        baked.withUnsafeMutableBytes { buffer in
            context.render(
                output,
                toBitmap: buffer.baseAddress!,
                rowBytes: bytesPerRow,
                bounds: input.extent,
                format: .RGBAf,
                colorSpace: sRGB
            )
        }
        var text = "TITLE \"\(preset.name.replacingOccurrences(of: "\"", with: "'"))\"\n"
        text += "LUT_3D_SIZE \(size)\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        text.reserveCapacity(text.count + count * 28)
        func channel(_ value: Float) -> String {
            String(format: "%.6f", min(1, max(0, value.isFinite ? value : 0)))
        }
        for index in 0..<count {
            text += "\(channel(baked[index * 4])) \(channel(baked[index * 4 + 1])) \(channel(baked[index * 4 + 2]))\n"
        }
        return Output(text: text, lostSettings: lostSettings(preset.recipe))
    }
}
