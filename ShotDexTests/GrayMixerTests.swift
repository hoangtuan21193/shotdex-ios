import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15 AC-10, AC-15 — the Black & White mix.
struct GrayMixerTests {
    /// Three ColorChecker patches in sRGB: Blue, Yellow, Neutral 5.
    private static let patches: [(name: String, rgb: (UInt8, UInt8, UInt8))] = [
        ("blue", (56, 61, 150)), ("yellow", (231, 199, 31)), ("neutral5", (122, 122, 121)),
    ]
    private static let side = 8

    private static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    private static func chart() -> CIImage {
        let width = side * patches.count
        var bytes = [UInt8](repeating: 255, count: width * side * 4)
        for y in 0..<side {
            for x in 0..<width {
                let (r, g, b) = patches[x / side].rgb
                let index = (y * width + x) * 4
                bytes[index] = r; bytes[index + 1] = g; bytes[index + 2] = b
            }
        }
        return CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4,
            size: CGSize(width: width, height: side), format: .RGBA8, colorSpace: sRGB
        )
    }

    /// The centre pixel of each patch, as sRGB bytes.
    private static func read(_ image: CIImage) -> [String: (Int, Int, Int)] {
        let width = side * patches.count
        var bytes = [UInt8](repeating: 0, count: width * side * 4)
        CIContext().render(
            image, toBitmap: &bytes, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: side), format: .RGBA8, colorSpace: sRGB
        )
        var result: [String: (Int, Int, Int)] = [:]
        for (index, patch) in patches.enumerated() {
            let offset = ((side / 2) * width + index * side + side / 2) * 4
            result[patch.name] = (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }
        return result
    }

    private static func render(_ color: PhotoColorRecipe, warmth: Double = 0) -> [String: (Int, Int, Int)] {
        var adjustments = PhotoAdjustments()
        adjustments.warmth = warmth
        let lit = PhotoRenderService.applyLight(adjustments, to: chart(), appliesExposure: true)
        return read(PhotoRenderService.applyColor(color, blackAndWhite: true, to: lit))
    }

    private static func expectGrey(_ patches: [String: (Int, Int, Int)], sourceLocation: SourceLocation = #_sourceLocation) {
        for (name, (r, g, b)) in patches {
            #expect(abs(r - g) <= 1 && abs(g - b) <= 1, "\(name) is not grey: \(r) \(g) \(b)", sourceLocation: sourceLocation)
        }
    }

    /// AC-10. Blue −60 darkens the blue patch by at least 15% and leaves the
    /// yellow and neutral patches within 2/255; everything stays grey.
    @Test func blueDarkensOnlyBlue() {
        let plain = Self.render(PhotoColorRecipe())
        var color = PhotoColorRecipe()
        color.grayMixer.blue = -0.6
        let mixed = Self.render(color)

        Self.expectGrey(plain)
        Self.expectGrey(mixed)
        let before = Double(plain["blue"]!.0), after = Double(mixed["blue"]!.0)
        #expect(after <= before * 0.85, "blue went from \(before) to \(after)")
        #expect(abs(mixed["yellow"]!.0 - plain["yellow"]!.0) <= 2)
        #expect(abs(mixed["neutral5"]!.0 - plain["neutral5"]!.0) <= 2)
    }

    /// AC-15. Black & White runs after white balance, and white balance is
    /// channel gains, so warming the photo brightens yellow in the grey version.
    @Test func temperatureShiftsTheGreyMix() {
        let neutral = Self.render(PhotoColorRecipe())
        let warm = Self.render(PhotoColorRecipe(), warmth: 0.3)
        Self.expectGrey(warm)
        #expect(warm["yellow"]!.0 - neutral["yellow"]!.0 >= 3, "yellow \(neutral["yellow"]!.0) → \(warm["yellow"]!.0)")
        // Blue's brightness sits mostly in green, which the gains are normalised
        // on, so it does not visibly darken — it must not brighten.
        #expect(warm["blue"]!.0 <= neutral["blue"]!.0, "blue \(neutral["blue"]!.0) → \(warm["blue"]!.0)")
    }
}
