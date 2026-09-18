import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// Sharing without the location. The promise is narrow and worth pinning down:
/// the coordinate goes, and nothing else does.
struct ShareLocationStrippingTests {

    /// A one-pixel JPEG carrying a GPS position and a camera make/model.
    private func photoData() throws -> Data {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.6812,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7671,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: "EOS R6",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifISOSpeedRatings: [200],
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    @Test func theCoordinateIsGone() throws {
        let original = try photoData()
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let stripped = try #require(PhotoShareSheet.stripLocation(from: original))
        #expect(try properties(of: stripped)[kCGImagePropertyGPSDictionary] == nil)
    }

    /// The camera, the lens and the exposure are why a photographer shares a
    /// photo at all. Dropping them alongside the coordinate would be a bug.
    @Test func everythingElseSurvives() throws {
        let stripped = try #require(PhotoShareSheet.stripLocation(from: try photoData()))
        let props = try properties(of: stripped)

        let tiff = try #require(props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "Canon")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "EOS R6")

        let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] == [200])
    }

    @Test func thePictureItselfIsUntouched() throws {
        let original = try photoData()
        let stripped = try #require(PhotoShareSheet.stripLocation(from: original))
        let props = try properties(of: stripped)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 8)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 8)
    }

    /// Something that is not an image comes back as nothing, and the caller
    /// shares the bytes it already had rather than nothing at all.
    @Test func garbageInGivesNothingBack() {
        #expect(PhotoShareSheet.stripLocation(from: Data([0x00, 0x01, 0x02])) == nil)
    }
}
