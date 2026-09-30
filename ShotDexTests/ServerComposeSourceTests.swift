import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-17.06 §5b: what Collage, Combine and the Video Studio read from a
/// server original on this device — at the size asked, with the camera's
/// date, under the file's own name.
@Suite struct ServerComposeSourceTests {
    /// A flat-colour JPEG (no people, no scene) with an EXIF capture date.
    static func writeJPEG(width: Int, height: Int, date: String?, to url: URL) throws {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let date {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexServerEdit-compose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// AC-84: a 6000×4000 original comes back at the long side asked, never
    /// the full frame.
    @Test func decodesAtTheSizeAsked() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("DSCF1000.JPG")
        try Self.writeJPEG(width: 6000, height: 4000, date: nil, to: url)

        let image = try #require(PhotoOriginFile.image(at: url, maxPixelSize: 1600))
        #expect(max(image.width, image.height) == 1600)
        #expect(image.width > image.height)
        let small = try #require(PhotoOriginFile.image(at: url, maxPixelSize: 300))
        #expect(max(small.width, small.height) == 300)
    }

    /// The camera's date comes from the file, and the name from the server.
    @Test func captureDateAndNameComeFromTheFile() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("DSCF1001.JPG")
        try Self.writeJPEG(width: 64, height: 48, date: "2026:09:28 07:15:30", to: url)
        let entry = RemoteEntry(name: "DSCF1001.JPG", isDirectory: false, size: 1, modified: nil)
        let origin = PhotoEditOrigin.serverFile(FetchedServerPhoto(
            serverId: "S1", folder: "Trip", photo: ServerPhoto(files: [entry]),
            files: [FetchedFile(file: entry, url: url, sha256: "")]
        ))

        #expect(origin.filename == "DSCF1001.JPG")
        let date = try #require(origin.captureDate)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 28)
        #expect(parts.hour == 7 && parts.minute == 15 && parts.second == 30)
        #expect(PhotoOriginFile.properties(at: url)[kCGImagePropertyPixelWidth] as? Int == 64)
    }

    @Test func unreadableFileGivesNothing() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("broken.JPG")
        try Data("not an image".utf8).write(to: url)
        #expect(PhotoOriginFile.image(at: url, maxPixelSize: 100) == nil)
        #expect(PhotoOriginFile.captureDate(at: url) == nil)
    }
}
