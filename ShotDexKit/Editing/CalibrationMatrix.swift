import Foundation
import simd

/// Lightroom's Calibration as a 3×3 matrix on linear RGB.
///
/// Each primary is moved: Hue turns it around the grey axis, Saturation pushes
/// it away from or toward that axis. The matrix whose columns are the moved
/// primaries is then normalised row by row so white stays white — Calibration
/// changes colours, not white balance (FS-03.15a §3).
public enum CalibrationMatrix {
    /// Turn of a primary at ±100, in linear light. Seen in sRGB hue a real
    /// patch moves about 2.5× this, so ±100 reads as roughly ±25° there —
    /// Lightroom's Red Hue +30 moves a red patch by a few degrees, not tens.
    static let maximumTurnDegrees = 10.0
    /// Saturation +100 doubles a primary's distance from grey; −100 removes it.
    static let saturationReach = 1.0

    public static func matrix(for calibration: PhotoCalibration) -> simd_double3x3 {
        let red = moved(SIMD3(1, 0, 0), hue: calibration.redHue, saturation: calibration.redSaturation)
        let green = moved(SIMD3(0, 1, 0), hue: calibration.greenHue, saturation: calibration.greenSaturation)
        let blue = moved(SIMD3(0, 0, 1), hue: calibration.blueHue, saturation: calibration.blueSaturation)
        var rows = simd_double3x3(columns: (red, green, blue)).transpose
        for index in 0..<3 {
            let row = rows[index]
            let sum = row.x + row.y + row.z
            rows[index] = abs(sum) > 1e-9 ? row / sum : SIMD3(repeating: 1.0 / 3)
        }
        // Stored as columns of the transpose: `rows[i]` is output channel i.
        return rows
    }

    static func moved(_ primary: SIMD3<Double>, hue: Double, saturation: Double) -> SIMD3<Double> {
        let grey = SIMD3(repeating: (primary.x + primary.y + primary.z) / 3)
        var offset = primary - grey
        offset *= max(0, 1 + min(1, max(-1, saturation)) * saturationReach)
        let angle = min(1, max(-1, hue)) * maximumTurnDegrees * .pi / 180
        return grey + rotated(offset, aroundGreyBy: angle)
    }

    /// Rodrigues around (1,1,1)/√3. A positive angle carries red toward
    /// yellow — up the hue wheel.
    static func rotated(_ vector: SIMD3<Double>, aroundGreyBy angle: Double) -> SIMD3<Double> {
        let axis = SIMD3(repeating: 1 / 3.0.squareRoot())
        let cosine = cos(angle), sine = sin(angle)
        return vector * cosine + cross(axis, vector) * sine + axis * dot(axis, vector) * (1 - cosine)
    }
}
