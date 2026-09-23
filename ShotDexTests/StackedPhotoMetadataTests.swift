import Foundation
import ImageIO
import Testing
@testable import ShotDex

/// FS-01.10 AC-14: the stacked photo keeps the first frame's gear and date.
struct StackedPhotoMetadataTests {
    private let frame: [String: Any] = [
        kCGImagePropertyPixelWidth as String: 6000,
        kCGImagePropertyOrientation as String: 6,
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFMake as String: "OM Digital Solutions",
            kCGImagePropertyTIFFModel as String: "OM-1",
            kCGImagePropertyTIFFOrientation as String: 6,
        ],
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifLensModel as String: "M.Zuiko 90mm F3.5 Macro",
            kCGImagePropertyExifDateTimeOriginal as String: "2026:09:20 10:15:03",
            kCGImagePropertyExifSubjectDistance as String: 0.31,
            kCGImagePropertyExifPixelXDimension as String: 6000,
        ],
        kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 35.68],
    ]

    @Test func cameraLensDateAndPlaceSurvive() {
        let out = StackedPhotoMetadata.properties(fromFirstFrame: frame)
        let tiff = out[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = out[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "OM-1")
        #expect(tiff?[kCGImagePropertyTIFFMake as String] as? String == "OM Digital Solutions")
        #expect(exif?[kCGImagePropertyExifLensModel as String] as? String == "M.Zuiko 90mm F3.5 Macro")
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:09:20 10:15:03")
        #expect(out[kCGImagePropertyGPSDictionary as String] != nil)
    }

    @Test func whatNoLongerDescribesTheResultIsDropped() {
        let out = StackedPhotoMetadata.properties(fromFirstFrame: frame)
        let exif = out[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = out[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifSubjectDistance as String] == nil)
        #expect(exif?[kCGImagePropertyExifPixelXDimension as String] == nil)
        #expect(out[kCGImagePropertyPixelWidth as String] == nil)
        #expect(tiff?[kCGImagePropertyTIFFOrientation as String] == nil)
        #expect(out[kCGImagePropertyOrientation as String] as? Int == 1)
    }
}

/// FS-01.10 AC-14 end to end at the encoder: the JPEG that gets saved reads
/// back with the first frame's gear.
struct StackedPhotoJPEGTests {
    @Test func theSavedJPEGReadsBackWithTheFirstFramesGear() throws {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let first: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFModel as String: "OM-1"],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "M.Zuiko 90mm F3.5 Macro",
                kCGImagePropertyExifDateTimeOriginal as String: "2026:09:20 10:15:03",
                kCGImagePropertyExifSubjectDistance as String: 0.31,
            ],
        ]
        let data = try #require(StackedPhotoMetadata.jpegData(
            context.makeImage()!, properties: StackedPhotoMetadata.properties(fromFirstFrame: first), quality: 0.95))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let read = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let tiff = read[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = read[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "OM-1")
        #expect(exif?[kCGImagePropertyExifLensModel as String] as? String == "M.Zuiko 90mm F3.5 Macro")
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:09:20 10:15:03")
        #expect(exif?[kCGImagePropertyExifSubjectDistance as String] == nil)
        #expect(read[kCGImagePropertyPixelWidth as String] as? Int == 64)
    }
}

/// FS-01.10 AC-13 at the folder: nothing outlives the save.
struct PhotoStackSessionTests {
    @Test func theFolderIsGoneAfterRemove() throws {
        let session = try PhotoStackSession()
        let url = try session.store(Data([1, 2, 3]), index: 0)
        #expect(FileManager.default.fileExists(atPath: url.path))
        session.remove()
        #expect(!FileManager.default.fileExists(atPath: session.folder.path))
    }

    @Test func theFolderIsGoneWhenTheSessionIsDropped() throws {
        var session: PhotoStackSession? = try PhotoStackSession()
        let folder = session!.folder
        _ = try session!.store(Data([1]), index: 0)
        session = nil
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
