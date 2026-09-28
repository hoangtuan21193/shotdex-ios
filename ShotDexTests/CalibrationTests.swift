import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-03.15 AC-12, AC-13 — Calibration.
struct CalibrationTests {
    private static let patches: [(name: String, rgb: (UInt8, UInt8, UInt8))] = [
        ("red", (175, 54, 60)), ("blue", (56, 61, 150)), ("neutral5", (122, 122, 121)),
        ("white", (243, 243, 242)), ("black", (52, 52, 52)),
    ]
    private static let side = 8
    private static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    private static func render(_ calibration: PhotoCalibration) -> [String: (Double, Double, Double)] {
        let width = side * patches.count
        var bytes = [UInt8](repeating: 255, count: width * side * 4)
        for y in 0..<side {
            for x in 0..<width {
                let (r, g, b) = patches[x / side].rgb
                let index = (y * width + x) * 4
                bytes[index] = r; bytes[index + 1] = g; bytes[index + 2] = b
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4,
            size: CGSize(width: width, height: side), format: .RGBA8, colorSpace: sRGB
        )
        let output = PhotoRenderService.applyCalibration(calibration, to: input)
        var result = [UInt8](repeating: 0, count: width * side * 4)
        CIContext().render(
            output, toBitmap: &result, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: side), format: .RGBA8, colorSpace: sRGB
        )
        var values: [String: (Double, Double, Double)] = [:]
        for (index, patch) in patches.enumerated() {
            let offset = ((side / 2) * width + index * side + side / 2) * 4
            values[patch.name] = (Double(result[offset]), Double(result[offset + 1]), Double(result[offset + 2]))
        }
        return values
    }

    /// Hue in degrees and HSV saturation of an sRGB triple.
    private static func hueAndSaturation(_ rgb: (Double, Double, Double)) -> (hue: Double, saturation: Double) {
        let (r, g, b) = (rgb.0 / 255, rgb.1 / 255, rgb.2 / 255)
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        guard delta > 0 else { return (0, 0) }
        var hue: Double
        if maximum == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == g { hue = 60 * ((b - r) / delta + 2) }
        else { hue = 60 * ((r - g) / delta + 4) }
        if hue < 0 { hue += 360 }
        return (hue, delta / maximum)
    }

    private static func hueShift(_ from: Double, _ to: Double) -> Double {
        var shift = to - from
        if shift > 180 { shift -= 360 }
        if shift < -180 { shift += 360 }
        return shift
    }

    /// AC-12. Red Hue +30 turns the red patch toward orange by 4°–12°, leaves
    /// Neutral 5 within 1/255 and moves blue by at most 2°.
    @Test func redHueMovesRedTowardOrange() {
        let plain = Self.render(PhotoCalibration())
        let turned = Self.render(PhotoCalibration(redHue: 0.3))
        let redShift = Self.hueShift(Self.hueAndSaturation(plain["red"]!).hue, Self.hueAndSaturation(turned["red"]!).hue)
        #expect(redShift >= 4 && redShift <= 12, "red moved \(redShift)°")
        let blueShift = Self.hueShift(Self.hueAndSaturation(plain["blue"]!).hue, Self.hueAndSaturation(turned["blue"]!).hue)
        #expect(abs(blueShift) <= 2, "blue moved \(blueShift)°")
        let (n0, n1) = (plain["neutral5"]!, turned["neutral5"]!)
        #expect(abs(n0.0 - n1.0) <= 1 && abs(n0.1 - n1.1) <= 1 && abs(n0.2 - n1.2) <= 1)
    }

    /// AC-13. Blue Saturation +50 makes the blue patch at least 10% more
    /// saturated and keeps every neutral within 1/255 — the matrix keeps white.
    @Test func saturationKeepsGreysGrey() {
        let plain = Self.render(PhotoCalibration())
        let pushed = Self.render(PhotoCalibration(blueSaturation: 0.5))
        let before = Self.hueAndSaturation(plain["blue"]!).saturation
        let after = Self.hueAndSaturation(pushed["blue"]!).saturation
        #expect(after >= before * 1.1, "blue saturation \(before) → \(after)")
        for name in ["neutral5", "white", "black"] {
            let (a, b) = (plain[name]!, pushed[name]!)
            #expect(abs(a.0 - b.0) <= 1 && abs(a.1 - b.1) <= 1 && abs(a.2 - b.2) <= 1, "\(name) moved")
        }
    }

    /// Every row of the matrix sums to one, whatever the sliders say.
    @Test func matrixAlwaysKeepsWhite() {
        let extreme = PhotoCalibration(redHue: 1, redSaturation: -1, greenHue: -1, greenSaturation: 1, blueHue: 0.7, blueSaturation: 0.4)
        let m = CalibrationMatrix.matrix(for: extreme)
        for index in 0..<3 {
            let row = m[index]
            #expect(abs(row.x + row.y + row.z - 1) < 1e-9)
        }
    }
}
