import Foundation
import ImageIO
import Testing
@testable import ShotDex

/// FS-01.11 §6 — AC-15: the merge carries the reference frame's camera,
/// lens, date and place, and none of its exposure.
struct HDRMetadataTests {
    @Test func theReferencesGearStaysAndItsExposureGoes() {
        let source: [String: Any] = [
            kCGImagePropertyPixelWidth as String: 6000,
            kCGImagePropertyOrientation as String: 6,
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFMake as String: "Canon",
                                                       kCGImagePropertyTIFFModel as String: "EOS R6"],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "RF24-105mm F4 L IS USM",
                kCGImagePropertyExifDateTimeOriginal as String: "2026:09:30 17:12:03",
                kCGImagePropertyExifExposureTime as String: 1.0 / 125,
                kCGImagePropertyExifFNumber as String: 8.0,
                kCGImagePropertyExifISOSpeedRatings as String: [100],
                kCGImagePropertyExifISOSpeed as String: 100,
                kCGImagePropertyExifExposureBiasValue as String: 0.0,
                kCGImagePropertyExifShutterSpeedValue as String: 6.97,
                kCGImagePropertyExifApertureValue as String: 6.0,
            ],
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 35.6],
            kCGImagePropertyMakerCanonDictionary as String: ["x": 1],
        ]
        let result = StackedPhotoMetadata.properties(fromReference: source)
        let tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "EOS R6")
        #expect(exif[kCGImagePropertyExifLensModel as String] as? String == "RF24-105mm F4 L IS USM")
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:09:30 17:12:03")
        #expect(result[kCGImagePropertyGPSDictionary as String] != nil)
        for key in [kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber, kCGImagePropertyExifISOSpeedRatings,
                    kCGImagePropertyExifISOSpeed, kCGImagePropertyExifExposureBiasValue,
                    kCGImagePropertyExifShutterSpeedValue, kCGImagePropertyExifApertureValue] {
            #expect(exif[key as String] == nil, "\(key) should be gone")
        }
        #expect(result[kCGImagePropertyMakerCanonDictionary as String] == nil)
        #expect(result[kCGImagePropertyOrientation as String] as? Int == 1)
        #expect(result[kCGImagePropertyPixelWidth as String] == nil)
    }
}
