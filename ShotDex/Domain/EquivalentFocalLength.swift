import Foundation

/// Computes full-frame equivalent focal length. Pure Swift.
enum EquivalentFocalLength {

    /// `fullFrameEquivalent = actualFocalLength × cropFactor`
    static func calculate(actualFocalLength: Double?, cropFactor: Double?) -> Double? {
        guard let actualFocalLength, actualFocalLength > 0,
              let cropFactor, cropFactor > 0
        else { return nil }
        return actualFocalLength * cropFactor
    }

    /// Best equivalent focal length following the spec priority:
    /// 1. `FocalLenIn35mmFilm` from EXIF when present and plausible
    /// 2. actual focal length × crop factor
    /// 3. nil when the crop factor is unknown
    static func resolve(
        exif35mm: Double?,
        actualFocalLength: Double?,
        cropFactor: Double?
    ) -> Double? {
        if let exif35mm, isPlausible35mm(exif35mm) {
            return exif35mm
        }
        return calculate(actualFocalLength: actualFocalLength, cropFactor: cropFactor)
    }

    /// EXIF sometimes carries 0 or garbage in FocalLenIn35mmFilm.
    static func isPlausible35mm(_ value: Double) -> Bool {
        value >= 1 && value <= 3000 && value.isFinite
    }
}
