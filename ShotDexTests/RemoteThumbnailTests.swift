import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-17.01 §3: thumbnails from the head of the file, more only when needed.
@Suite struct RemoteThumbnailTests {
    /// A JPEG of `width`×`width*2/3`, optionally with an EXIF thumbnail and a
    /// capture date.
    static func jpeg(width: Int, embedsThumbnail: Bool = false, date: String? = nil) -> Data {
        let height = width * 2 / 3
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for y in stride(from: 0, to: height, by: 8) {
            context.setFillColor(red: CGFloat(y % 256) / 255, green: 0.4, blue: CGFloat((y * 7) % 256) / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: width, height: 8))
        }
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if embedsThumbnail {
            properties[kCGImageDestinationEmbedThumbnail] = true
            properties[kCGImageDestinationImageMaxPixelSize] = width
        }
        if let date {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// `size` bytes of noise with `pieces` written at their offsets.
    static func blob(size: Int, _ pieces: [(Int, Data)]) -> Data {
        var data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) })
        // No stray start-of-image markers in the noise.
        for index in data.indices where data[index] == 0xFF { data[index] = 0xFE }
        for (offset, piece) in pieces { data.replaceSubrange(offset..<(offset + piece.count), with: piece) }
        return data
    }

    private func thumbnailer(_ client: InMemoryRemoteFileClient) -> RemoteThumbnailer {
        RemoteThumbnailer(client: client)
    }

    /// AC-3: a CR3-like file — a 160 px thumbnail early, a 1200 px preview
    /// at ~90 KB (the `PRVW` layout measured on real files) — gives a sharp
    /// tile from the head alone.
    @Test func cr3EmbeddedPreview() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("P/A.CR3", Self.blob(size: 3_000_000, [(13_000, Self.jpeg(width: 160)), (90_000, Self.jpeg(width: 1200))]))
        let photo = ServerPhoto(files: [RemoteEntry(name: "A.CR3", isDirectory: false, size: 3_000_000, modified: nil)])
        let result = try await thumbnailer(client).thumbnail(for: photo, in: "P")
        let thumbnail = try #require(result.thumbnail)
        #expect(thumbnail.sourceLongSide == 1200)
        #expect(max(thumbnail.image.width, thumbnail.image.height) == 400)
        #expect(client.bytesRead <= EmbeddedPreview.secondRead)
    }

    /// A preview that ends past 256 KB is found by the longer read.
    @Test func secondReadFindsALaterPreview() async throws {
        let client = InMemoryRemoteFileClient()
        let big = Self.jpeg(width: 2400)
        client.put("P/B.ARW", Self.blob(size: 4_000_000, [(200_000, big)]))
        #expect(200_000 + big.count > EmbeddedPreview.firstRead)
        let photo = ServerPhoto(files: [RemoteEntry(name: "B.ARW", isDirectory: false, size: 4_000_000, modified: nil)])
        let result = try await thumbnailer(client).thumbnail(for: photo, in: "P")
        #expect(result.thumbnail?.sourceLongSide == 2400)
        #expect(client.bytesRead == EmbeddedPreview.secondRead)
    }

    /// AC-4: a JPEG whose only head preview is a 160 px EXIF thumbnail is
    /// downloaded whole (it is small) and the tile comes from the real image.
    @Test func smallExifThumbUpgrades() async throws {
        let client = InMemoryRemoteFileClient()
        let file = Self.jpeg(width: 2000, embedsThumbnail: true, date: "2022:10:10 16:23:07")
        client.put("P/C.JPG", Self.blob(size: 0, []) + file + Self.blob(size: 400_000, []))
        let size = Int64(file.count + 400_000)
        let photo = ServerPhoto(files: [RemoteEntry(name: "C.JPG", isDirectory: false, size: size, modified: nil)])
        let result = try await thumbnailer(client).thumbnail(for: photo, in: "P")
        #expect(result.thumbnail?.sourceLongSide == 2000)
        #expect(result.captureDate != nil)
    }

    /// AC-5: a RAW with no preview in its first megabyte is not downloaded.
    @Test func rawWithoutPreviewStaysIcon() async throws {
        let client = InMemoryRemoteFileClient()
        client.put("P/D.NEF", Self.blob(size: 6_000_000, []))
        let photo = ServerPhoto(files: [RemoteEntry(name: "D.NEF", isDirectory: false, size: 6_000_000, modified: nil)])
        let result = try await thumbnailer(client).thumbnail(for: photo, in: "P")
        #expect(result.thumbnail == nil)
        #expect(client.bytesRead == EmbeddedPreview.secondRead)
    }

    /// RAF: the preview sits behind a pointer in the header.
    @Test func rafPreviewFollowsTheHeaderPointer() async throws {
        let preview = Self.jpeg(width: 1600)
        var header = Data("FUJIFILMCCD-RAW 0201FF383501".utf8)
        header += Data(repeating: 0, count: 84 - header.count)
        let offset = 2_000_000
        for word in [offset, preview.count] { header += withUnsafeBytes(of: UInt32(word).bigEndian) { Data($0) } }
        let client = InMemoryRemoteFileClient()
        client.put("P/E.RAF", Self.blob(size: 3_000_000, [(0, header), (offset, preview)]))
        let photo = ServerPhoto(files: [RemoteEntry(name: "E.RAF", isDirectory: false, size: 3_000_000, modified: nil)])
        let result = try await thumbnailer(client).thumbnail(for: photo, in: "P")
        // ImageIO thumbnails the whole preview JPEG itself: 400 px, sharp.
        #expect((result.thumbnail?.sourceLongSide ?? 0) >= EmbeddedPreview.sharpEnough)
        #expect(client.bytesRead == EmbeddedPreview.firstRead + preview.count)
    }

    /// A cut-off JPEG is not a preview, and a JPEG's nested EXIF thumbnail
    /// does not end the outer one early.
    @Test func onlyCompleteJPEGsCount() {
        let full = Self.jpeg(width: 1000, embedsThumbnail: true)
        let spans = EmbeddedPreview.embeddedJPEGs(in: full)
        #expect(spans.map(\.longSide) == [1000])
        #expect(spans.first?.range == 0..<full.count)
        // Cut in half: the outer image is gone, the nested thumbnail is whole.
        #expect(EmbeddedPreview.embeddedJPEGs(in: full.prefix(full.count / 2)).allSatisfy { $0.longSide < 1000 })
    }

    /// Date Taken for RAW heads ImageIO can't read: the EXIF date string.
    @Test func captureDateFallsBackToTheEXIFString() throws {
        var head = Self.blob(size: 4_000, [])
        head.replaceSubrange(1_000..<1_020, with: Data("2021:05:15 13:05:25\u{0}".utf8))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try #require(EmbeddedPreview.captureDate(from: head, timeZone: tokyo))
        #expect(date == Date(timeIntervalSince1970: 1_621_051_525))
        #expect(EmbeddedPreview.firstEXIFDateString(in: Data("2021:05:15 13:05:25X".utf8)) == nil)
    }
}
