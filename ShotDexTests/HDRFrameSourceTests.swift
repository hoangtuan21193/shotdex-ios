import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-01.11 §5 — AC-21 (the source half): frames read linear, RAW or not.
@Suite struct HDRFrameSourceTests {
    static let context = CIContext(options: [.workingFormat: CIFormat.RGBAh])

    /// A flat sRGB JPEG with an exposure in its EXIF.
    static func jpeg(width: Int, height: Int, grey: CGFloat, exif: [CFString: Any]) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [grey, grey, grey, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hdr-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [
            kCGImagePropertyExifDictionary: exif, kCGImageDestinationLossyCompressionQuality: 1,
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static func centre(_ image: CIImage) -> Float {
        var pixel = [Float](repeating: 0, count: 4)
        let p = CGPoint(x: image.extent.midX, y: image.extent.midY)
        pixel.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: 16, bounds: CGRect(origin: p, size: CGSize(width: 1, height: 1)),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        }
        return pixel[1]
    }

    @Test func aJPEGReadsItsExposureAndComesBackLinear() throws {
        let url = try Self.jpeg(width: 64, height: 64, grey: 188.0 / 255, exif: [
            kCGImagePropertyExifExposureTime: 1.0 / 125, kCGImagePropertyExifISOSpeedRatings: [200],
            kCGImagePropertyExifFNumber: 5.6, kCGImagePropertyExifExposureBiasValue: -1.0,
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try #require(HDRFrameSource.frameFile(at: url))
        #expect(!file.isRAW)
        #expect(abs((file.shutterSeconds ?? 0) - 1.0 / 125) < 1e-6)
        #expect(file.iso == 200)
        #expect(abs((file.aperture ?? 0) - 5.6) < 1e-6)
        #expect(file.exposureBias == -1)
        // sRGB 188 is linear 0.503: the curve is undone on the way in.
        let image = try #require(HDRFrameSource.linearImage(of: file, fromRAW: true, maxPixelSize: nil))
        #expect(abs(Self.centre(image) - 0.503) < 0.01)
    }

    @Test func aPreviewIsReadSmallAndSaysHowSmall() throws {
        let url = try Self.jpeg(width: 3200, height: 1600, grey: 0.5, exif: [:])
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try #require(HDRFrameSource.frameFile(at: url))
        let image = try #require(HDRFrameSource.linearImage(of: file, fromRAW: true, maxPixelSize: HDRFrameSource.previewEdge))
        #expect(image.extent.size == CGSize(width: 1600, height: 800))
        #expect(abs(HDRFrameSource.pixelScale(of: file, image: image) - 0.5) < 1e-6)
        #expect(file.orderFrame(id: 0).measuredLog2Brightness == nil)
        let measured = try #require(HDRFrameSource.medianLog2Luminance(of: image, context: Self.context))
        #expect(abs(measured - log2(0.214)) < 0.1)   // sRGB 0.5 is linear 0.214
    }

    /// AC-21: a RAW reads linear for an all-RAW series, and through the
    /// decoder's tone curve — like the JPEGs beside it — for a mixed one.
    @Test(.enabled(if: HDRExportTests.hasRawFixture)) func aRAWReadsLinearOrProcessed() throws {
        let file = try #require(HDRFrameSource.frameFile(at: HDRExportTests.rawFixture))
        #expect(file.isRAW)
        #expect(file.shutterSeconds != nil && file.iso != nil && file.aperture != nil)
        let linear = try #require(HDRFrameSource.linearImage(of: file, fromRAW: true, maxPixelSize: HDRFrameSource.previewEdge))
        let processed = try #require(HDRFrameSource.linearImage(of: file, fromRAW: false, maxPixelSize: HDRFrameSource.previewEdge))
        #expect(max(linear.extent.width, linear.extent.height) <= 1601)
        let a = try #require(HDRFrameSource.medianLog2Luminance(of: linear, context: Self.context))
        let b = try #require(HDRFrameSource.medianLog2Luminance(of: processed, context: Self.context))
        print(String(format: "HDR AC-21 RAW median: linear %.2f, processed %.2f stops", a, b))
        #expect(b > a + 0.3)
        let mixed = HDRBracketOrder.series([file.orderFrame(id: 0), HDRFrameFile(url: file.url, isRAW: false).orderFrame(id: 1)])
        #expect(mixed.isMixedRAW && !mixed.mergesFromRAW)
    }
}
