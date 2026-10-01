import Foundation
import ImageIO

/// The metadata a combined photo carries (FS-01.10 AC-14): the first frame's
/// camera, lens, date and place, so filters and statistics still find it
/// under the gear it was shot with.
///
/// Dropped: what no longer describes the result — the frame's pixel size and
/// orientation (the render is upright and its own size), and subject
/// distance, which is one plane of a picture that is now sharp through all of
/// them.
enum StackedPhotoMetadata {
    static func properties(fromFirstFrame source: [String: Any]) -> [String: Any] {
        var result = source
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation,
                    kCGImagePropertyDepth, kCGImagePropertyProfileName] {
            result.removeValue(forKey: key as String)
        }
        if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            for key in [kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension,
                        kCGImagePropertyExifSubjectDistance, kCGImagePropertyExifSubjectDistRange] {
                exif.removeValue(forKey: key as String)
            }
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation as String)
            result[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        result[kCGImagePropertyOrientation as String] = 1
        return result
    }
}

extension StackedPhotoMetadata {
    /// An HDR merge's metadata (FS-01.11 §6, AC-15): the reference frame's,
    /// as for a stack, less its exposure — shutter, ISO, aperture and bias
    /// describe one frame of the series, not the merge.
    static func properties(fromReference source: [String: Any]) -> [String: Any] {
        var result = properties(fromFirstFrame: source)
        if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            for key in [kCGImagePropertyExifExposureTime, kCGImagePropertyExifShutterSpeedValue,
                        kCGImagePropertyExifFNumber, kCGImagePropertyExifApertureValue,
                        kCGImagePropertyExifISOSpeedRatings, kCGImagePropertyExifISOSpeed,
                        kCGImagePropertyExifRecommendedExposureIndex, kCGImagePropertyExifStandardOutputSensitivity,
                        kCGImagePropertyExifSensitivityType, kCGImagePropertyExifExposureBiasValue,
                        kCGImagePropertyExifBrightnessValue, kCGImagePropertyExifExposureIndex] {
                exif.removeValue(forKey: key as String)
            }
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        // A RAW's own dictionaries mean nothing on a JPEG or HEIC.
        for key in [kCGImagePropertyDNGDictionary, kCGImagePropertyCIFFDictionary, kCGImagePropertyRawDictionary,
                    kCGImagePropertyMakerCanonDictionary, kCGImagePropertyMakerNikonDictionary] {
            result.removeValue(forKey: key as String)
        }
        return result
    }
}

extension StackedPhotoMetadata {
    /// The combined picture as a JPEG carrying `properties` — what
    /// `properties(fromFirstFrame:)` kept — so the saved photo reads back with
    /// the first frame's camera, lens and date.
    static func jpegData(_ image: CGImage, properties: [String: Any], quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality as String] = quality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
