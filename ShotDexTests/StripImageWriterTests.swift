import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDexKit

/// The streamed writer panoramas and HDR merges are saved through.
struct StripImageWriterTests {
    /// A vertical gradient, white at the top, comes out white at the top and
    /// darkening row by row — whatever the strip height. Until 2026-10-01
    /// each strip came out upside down.
    @Test(arguments: [256, 512, 100]) func rowsComeOutInOrder(stripHeight: Int) throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 600)
        let gradient = try #require(CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: 600),
            "inputColor0": CIColor.black, "inputColor1": CIColor.white,
        ])?.outputImage).cropped(to: extent)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("strip-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try StripImageWriter.write(gradient, rect: extent, to: url, type: .png, quality: 1,
                                   context: CIContext(options: [.workingFormat: CIFormat.RGBAh]), stripHeight: stripHeight)
        let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        var pixels = [UInt8](repeating: 0, count: 32 * 600 * 4)
        let context = try #require(CGContext(data: &pixels, width: 32, height: 600, bitsPerComponent: 8, bytesPerRow: 128,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 600))
        let column = (0..<600).map { Int(pixels[$0 * 128]) }
        #expect(column[0] >= 250)
        #expect(column[599] <= 5)
        #expect(zip(column, column.dropFirst()).allSatisfy { $0 >= $1 }, "rows out of order: \(column.prefix(8))…")
    }
}
