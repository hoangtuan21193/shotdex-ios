import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDexKit
@testable import ShotDex

struct PresetDNGReaderTests {
    /// A small TIFF-family file carrying an XMP packet with crs:Vibrance, built
    /// here — no one's photo, no face.
    static func presetFile(pixels side: Int = 64) throws -> Data {
        let xmp = String(decoding: LightroomXMPReaderTests.preset(#"crs:Vibrance="+15""#), as: UTF8.self)
        let metadata = try #require(CGImageMetadataCreateFromXMPData(Data(xmp.utf8) as CFData))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// FS-03.14 AC-a3. The preset's XMP says Vibrance +15: the look has it,
    /// and no pixel was decoded to get there.
    @Test func readsXMPWithoutDecodingPixels() throws {
        PresetDNGReader.pixelDecodes = 0
        let settings = try PresetDNGReader.read(data: Self.presetFile(pixels: 1024))
        let result = LightroomMapping.map(settings)
        #expect(abs(result.recipe.adjustments[.vibrance] - 0.15) < 1e-9)
        #expect(PresetDNGReader.pixelDecodes == 0)
    }
}
