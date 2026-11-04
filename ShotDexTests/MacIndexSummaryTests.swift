import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-70: what the Mac says about the index. Expected numbers go
/// through the same formatters, so the suite holds in any locale.
@Suite struct MacIndexSummaryTests {
    private let counts = IndexStatusLine.Counts(photos: 54_027, videos: 1_204, bytes: 412_600_000_000)
    private func number(_ value: Int) -> String { value.formatted(.number) }

    /// A run going: how far, out of how many; what is read so far under it; a bar.
    @Test func indexingSaysHowFar() {
        let state = IndexStatusLine.State.indexing(processed: 12_400, total: 55_231)
        #expect(IndexStatusLine.title(state, counts: counts) == "Indexing \(number(12_400)) of \(number(55_231))")
        #expect(IndexStatusLine.detail(state, counts: counts) == "\(number(54_027)) photos · \(number(1_204)) videos read so far")
        #expect(abs((IndexStatusLine.fraction(state) ?? 0) - 12_400.0 / 55_231.0) < 0.0001)
    }

    /// A run still counting its work says so — never "up to date" — and draws no fraction.
    @Test func preparingIsARun() {
        #expect(IndexStatusLine.title(.preparing, counts: counts) == "Preparing to index…")
        #expect(IndexStatusLine.fraction(.preparing) == nil)
        #expect(IndexStatusLine.detail(.preparing, counts: .init(photos: 0, videos: 0)) == nil)
    }

    /// Finished: the split as the title; size, state and when under it; no bar.
    @Test func finishedSaysWhatAndWhen() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let last = now.addingTimeInterval(-120)
        let state = IndexStatusLine.State.upToDate(lastIndexed: last)
        #expect(IndexStatusLine.title(state, counts: counts) == "\(number(54_027)) photos · \(number(1_204)) videos")
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let size = Int64(412_600_000_000).formatted(.byteCount(style: .file))
        #expect(IndexStatusLine.detail(state, counts: counts, now: now)
                == "\(size) of originals · up to date · indexed \(formatter.localizedString(for: last, relativeTo: now))")
        #expect(IndexStatusLine.fraction(state) == nil)
        // Under a minute is "just now", not a count of seconds.
        #expect(IndexStatusLine.indexedAgo(now.addingTimeInterval(-6), now: now) == "indexed just now")
    }

    /// One of a kind is singular; no videos, no videos part.
    @Test func plurals() {
        #expect(IndexStatusLine.countsLine(.init(photos: 1, videos: 1)) == "1 photo · 1 video")
        #expect(IndexStatusLine.countsLine(.init(photos: 3, videos: 0)) == "3 photos")
    }

    /// Nothing ever read: said plainly, with nothing made up under it.
    @Test func neverIndexed() {
        let state = IndexStatusLine.State.upToDate(lastIndexed: nil)
        #expect(IndexStatusLine.title(state, counts: .init(photos: 0, videos: 0)) == "Not indexed yet")
        #expect(IndexStatusLine.detail(state, counts: .init(photos: 0, videos: 0)) == nil)
        #expect(IndexStatusLine.fraction(.indexing(processed: 0, total: 0)) == nil)
    }

    /// The query counts finished reads only, splits photos from videos, and sums known sizes.
    @Test func countsFinishedReadsOnly() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.upsert(row("p1", .photo, .indexed, size: 10_000_000))
        try store.upsert(row("p2", .photo, .noExif, size: nil))
        try store.upsert(row("v1", .video, .indexed, size: 10_000_000))
        // A placeholder the fast pass wrote: not read yet, not counted.
        try store.upsert(row("pending", .photo, .pendingRead, size: 5_000_000))
        let counts = try await LibraryQueries(database: database).indexSummaryCounts()
        #expect(counts == IndexStatusLine.Counts(photos: 2, videos: 1, bytes: 20_000_000))
    }

    private func row(_ assetId: String, _ kind: MediaKind, _ status: ExifStatus, size: Int?) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId, creationDate: 1_700_000_000, modificationDate: 1_700_000_000, mediaType: kind.storedValue,
            cameraManufacturer: nil, cameraModel: nil, normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil,
            iso: nil, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil, width: 6000, height: 4000, fileSize: size,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000, exifStatus: status.rawValue)
    }
}
