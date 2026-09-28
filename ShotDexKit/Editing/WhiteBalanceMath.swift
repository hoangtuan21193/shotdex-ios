import Foundation

/// The Warmth and Tint sliders as per-channel gains, the way Lightroom moves
/// white balance: the colour of a blackbody at the target temperature over
/// its colour at 6500 K, normalised on green. Neutrals keep roughly their
/// brightness, coloured areas do not — a warmer photo has brighter yellows
/// and darker blues, which is what lets Temp re-tone a Black & White
/// conversion (FS-03.15 AC-15). Core Image's temperature filter keeps
/// luminance, so it could not.
public enum WhiteBalanceMath {
    /// Kelvin the neutral moves by per unit of Warmth (the slider is −1…1).
    static let kelvinPerUnit = 3_000.0
    static let referenceKelvin = 6_500.0
    /// Green's gain per unit of Tint: + is magenta, so green drops.
    static let greenPerTint = 0.15

    /// Linear-light RGB of a blackbody, brightest channel at 1 (Tanner
    /// Helland's fit, sRGB-encoded, then decoded).
    static func blackbody(_ kelvin: Double) -> SIMD3<Double> {
        let t = min(400, max(10, kelvin / 100))
        let red = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green = t <= 66
            ? 99.4708025861 * log(t) - 161.1195681661
            : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func linear(_ value: Double) -> Double {
            let v = min(255, max(0, value)) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3(linear(red), linear(green), linear(blue))
    }

    /// Gains for the red, green and blue channels, in linear light.
    public static func gains(warmth: Double, tint: Double) -> SIMD3<Double> {
        let target = referenceKelvin - min(1, max(-1, warmth)) * kelvinPerUnit
        let ratio = blackbody(target) / blackbody(referenceKelvin)
        var gains = ratio / ratio.y
        gains.y *= 1 - min(1, max(-1, tint)) * greenPerTint
        return gains
    }
}
