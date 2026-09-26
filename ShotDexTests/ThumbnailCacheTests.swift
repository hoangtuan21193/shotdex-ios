import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// AC-6: a cached folder reopens without reading the server, and the cache
/// stays under its ceiling.
@Suite struct ThumbnailCacheTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexThumbCache-\(UUID().uuidString)", isDirectory: true)
    }

    private func key(_ name: String) -> RemoteThumbnailCache.Key {
        .init(connectionId: "S1", path: "P/\(name)", size: 3_000_000, modified: Date(timeIntervalSince1970: 1_000))
    }

    @Test func hitAndEviction() async throws {
        let cache = RemoteThumbnailCache(directory: directory())
        let client = InMemoryRemoteFileClient()
        client.put("P/A.CR3", RemoteThumbnailTests.blob(size: 3_000_000, [(90_000, RemoteThumbnailTests.jpeg(width: 1200))]))
        let photo = ServerPhoto(files: [RemoteEntry(name: "A.CR3", isDirectory: false, size: 3_000_000, modified: Date(timeIntervalSince1970: 1_000))])

        // First visit reads the server and stores the result.
        #expect(cache.entry(for: key("A.CR3")) == nil)
        let result = try await RemoteThumbnailer(client: client).thumbnail(for: photo, in: "P")
        cache.store(result, for: key("A.CR3"))
        let readFirstTime = client.bytesRead

        // Second visit: from disk, not one more byte from the server.
        let hit = try #require(cache.entry(for: key("A.CR3")))
        #expect(hit.image?.width == 400)
        #expect(hit.hasThumbnailResult)
        #expect(client.bytesRead == readFirstTime)

        // A changed file (new size) is a miss.
        let changed = RemoteThumbnailCache.Key(connectionId: "S1", path: "P/A.CR3", size: 3_000_001, modified: Date(timeIntervalSince1970: 1_000))
        #expect(cache.entry(for: changed) == nil)

        // "No preview" is remembered too.
        cache.store(RemoteThumbnailResult(thumbnail: nil, captureDate: nil), for: key("D.NEF"))
        let none = try #require(cache.entry(for: key("D.NEF")))
        #expect(none.image == nil && none.hasThumbnailResult)
    }

    @Test func evictsLeastRecentlyUsedOverTheLimit() throws {
        let image = try #require(Self.image())
        let folder = directory()
        let cache = RemoteThumbnailCache(directory: folder, limit: 60_000)
        for n in 0..<20 {
            cache.store(RemoteThumbnailResult(thumbnail: .init(image: image, sourceLongSide: 400), captureDate: nil), for: key("\(n).CR3"))
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        #expect(total <= 60_000)
        #expect(cache.entry(for: key("19.CR3")) != nil)
        #expect(cache.entry(for: key("0.CR3")) == nil)
    }

    private static func image() -> CGImage? {
        let context = CGContext(data: nil, width: 400, height: 266, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        for x in stride(from: 0, to: 400, by: 3) {
            context?.setFillColor(red: CGFloat(x % 7) / 7, green: CGFloat(x % 11) / 11, blue: 0.5, alpha: 1)
            context?.fill(CGRect(x: x, y: 0, width: 3, height: 266))
        }
        return context?.makeImage()
    }
}

/// AC-17: the three orders and both directions.
@Suite struct ServerFolderSortTests {
    private func photo(_ name: String, modified: String) -> ServerPhoto {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return ServerPhoto(files: [RemoteEntry(name: name, isDirectory: false, size: 1, modified: formatter.date(from: modified))])
    }

    @Test func threeOrders() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let photos = [photo("scan.png", modified: "2026-07-01"), photo("IMG_10.CR3", modified: "2026-09-01"), photo("IMG_2.JPG", modified: "2026-08-01")]
        let taken = ["IMG_10.CR3": formatter.date(from: "2026-01-03")!, "IMG_2.JPG": formatter.date(from: "2026-01-05")!]

        #expect(ServerPhotoSort.name.sorted(photos, ascending: true).map(\.id) == ["IMG_2.JPG", "IMG_10.CR3", "scan.png"])
        #expect(ServerPhotoSort.dateTaken.sorted(photos, ascending: true, captureDates: taken).map(\.id) == ["IMG_10.CR3", "IMG_2.JPG", "scan.png"])
        #expect(ServerPhotoSort.dateModified.sorted(photos, ascending: true).map(\.id) == ["scan.png", "IMG_2.JPG", "IMG_10.CR3"])

        #expect(ServerPhotoSort.name.sorted(photos, ascending: false).map(\.id) == ["scan.png", "IMG_10.CR3", "IMG_2.JPG"])
        #expect(ServerPhotoSort.dateTaken.sorted(photos, ascending: false, captureDates: taken).map(\.id) == ["scan.png", "IMG_2.JPG", "IMG_10.CR3"])
        #expect(ServerPhotoSort.dateModified.sorted(photos, ascending: false).map(\.id) == ["IMG_10.CR3", "IMG_2.JPG", "scan.png"])
    }

    @Test func undatedGoLast() {
        let photos = [ServerPhoto(files: [RemoteEntry(name: "b.png", isDirectory: false, size: 1, modified: nil)]), photo("a.jpg", modified: "2026-01-01")]
        #expect(ServerPhotoSort.dateModified.sorted(photos, ascending: false).map(\.id) == ["a.jpg", "b.png"])
    }
}
