import Foundation
import os
@testable import ShotDex

/// The "library" under `FakeOriginalFetcher` in the tests: every photo is on
/// the device, and fetching one writes a JPEG of the photo's own size. Tests
/// keep their photos small unless the size is the point.
final class FixtureOriginalFetcher: OriginalFetching, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())
    /// Ids fetched, in order.
    var fetched: [String] { lock.withLock { $0 } }

    func probe(_ item: OriginalItem) async -> OriginalAvailability { .local }

    func byteCount(of item: OriginalItem) async -> Int64? { item.byteCount }

    func fetch(_ item: OriginalItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        lock.withLock { $0.append(item.id) }
        var options = MetadataFixture.Options()
        options.width = item.photo.width
        options.height = item.photo.height
        options.xmp = false
        try MetadataFixture.encode(.jpeg, options: options).write(to: url)
        progress(1)
    }
}

extension OriginalItem {
    /// A small test photo.
    static func test(_ id: String, megabytes: Int64? = nil) -> OriginalItem {
        OriginalItem(id: id, filename: "IMG_\(id).JPG", photo: PixelSize(width: 60, height: 40),
                     byteCount: megabytes.map { $0 * 1_000_000 })
    }
}
