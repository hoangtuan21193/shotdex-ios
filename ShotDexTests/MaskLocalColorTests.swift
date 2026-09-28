import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDexKit

/// FS-03.15d AC-42, AC-43 — a mask's own colour controls.
struct MaskLocalColorTests {

    static let size = 256

    /// A flat PNG of one sRGB colour, for a full render.
    static func flatFile(red: UInt8, green: UInt8, blue: UInt8) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mask-colour-\(UUID().uuidString).png")
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for index in 0..<(size * size) {
            bytes[index * 4] = red; bytes[index * 4 + 1] = green; bytes[index * 4 + 2] = blue
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static func bytes(_ image: CIImage) -> [UInt8] {
        let context = CIContext()
        var values = [UInt8](repeating: 0, count: size * size * 4)
        context.render(image, toBitmap: &values, rowBytes: size * 4,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return values
    }

    static func hueDegrees(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let high = max(r, g, b), low = min(r, g, b), d = high - low
        guard d > 0 else { return 0 }
        var h: Double
        if high == r { h = (g - b) / d; if h < 0 { h += 6 } }
        else if high == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return h * 60
    }

    /// A radial mask on the 64×64 block at the top left.
    static func cornerMask() -> PhotoMask {
        var radial = PhotoMaskComponent(kind: .radialGradient)
        radial.center = NormalizedPoint(x: 0.125, y: 0.125)
        radial.radiusX = 0.125
        radial.radiusY = 0.125
        return PhotoMask(name: "Corner", component: radial)
    }

    static func render(_ recipe: PhotoEditRecipe, file: URL) async throws -> [UInt8] {
        let service = PhotoRenderService()
        let info = try await service.inspectSource(at: file)
        return bytes(try await service.render(source: info, recipe: recipe).image)
    }

    /// AC-42. Hue +30 on a corner mask, with a global Exposure +0.5: inside
    /// the mask the hue turns by at least 10°; the far corner's 32×32 block
    /// matches the render without Hue to 1/255.
    @Test func hueStaysInsideTheMask() async throws {
        let file = try Self.flatFile(red: 200, green: 120, blue: 60)
        defer { try? FileManager.default.removeItem(at: file) }
        var base = PhotoEditRecipe()
        base.adjustments.exposure = 0.5
        base.masks = [Self.cornerMask()]
        var turned = base
        turned.masks[0].adjustments.maskHue = 0.3

        let without = try await Self.render(base, file: file)
        let with = try await Self.render(turned, file: file)

        let centre = (32 * Self.size + 32) * 4
        let before = Self.hueDegrees(Double(without[centre]), Double(without[centre + 1]), Double(without[centre + 2]))
        let after = Self.hueDegrees(Double(with[centre]), Double(with[centre + 1]), Double(with[centre + 2]))
        var turn = abs(after - before)
        if turn > 180 { turn = 360 - turn }
        #expect(turn >= 10, "hue in the mask turned \(turn)°")

        var worst = 0
        for y in 208..<240 {
            for x in 208..<240 {
                for channel in 0..<3 {
                    let index = (y * Self.size + x) * 4 + channel
                    worst = max(worst, abs(Int(with[index]) - Int(without[index])))
                }
            }
        }
        #expect(worst <= 1, "far corner moved \(worst)/255")
    }

    /// The rotation keeps Rec. 709 luminance.
    @Test func hueRotationKeepsLuminance() {
        let colour = CIImage(color: CIColor(red: 0.8, green: 0.4, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let turned = PhotoRenderService.applyHueRotation(0.5, to: colour)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var v = [Float](repeating: 0, count: 4)
        context.render(turned, toBitmap: &v, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        let before = 0.213 * 0.8 + 0.715 * 0.4 + 0.072 * 0.2
        let after = 0.213 * Double(v[0]) + 0.715 * Double(v[1]) + 0.072 * Double(v[2])
        #expect(abs(after - before) < 1e-4)
    }

    /// AC-43. Color at hue 30°, saturation 50, over mid grey: the pixel's
    /// hue is 30° ± 5° and its Rec. 709 luminance moves by 1/255 at most.
    @Test func colorTintIsLuminanceNeutral() {
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let tinted = PhotoRenderService.applyTint(PhotoMaskTint(hue: 30.0 / 360, saturation: 0.5), to: grey)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var v = [Float](repeating: 0, count: 4)
        context.render(tinted, toBitmap: &v, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        let hue = Self.hueDegrees(Double(v[0]), Double(v[1]), Double(v[2]))
        #expect(abs(hue - 30) <= 5, "hue \(hue)°")
        let luma = 0.2126 * Double(v[0]) + 0.7152 * Double(v[1]) + 0.0722 * Double(v[2])
        #expect(abs(luma - 0.5) <= 1.0 / 255, "luminance \(luma)")
    }

    /// No Color picked, nothing written: a mask with a zero-saturation tint
    /// saves no tint key.
    @Test func noTintWritesNoKey() throws {
        var mask = Self.cornerMask()
        let plain = String(data: try JSONEncoder().encode(mask), encoding: .utf8) ?? ""
        #expect(!plain.contains("tint"))
        mask.tint = PhotoMaskTint(hue: 0.1, saturation: 0.4)
        let decoded = try JSONDecoder().decode(PhotoMask.self, from: JSONEncoder().encode(mask))
        #expect(decoded.tint == mask.tint)
    }
}
