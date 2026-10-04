import Foundation
import Testing
@testable import ShotDex

/// FS-19 §2 (sidecars and in-file ratings).
@Suite struct SidecarReaderTests {
    private let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))

    /// AC-52, Photos half: a Photos asset takes its stars from Photos only.
    /// The original carries a 4-star XMP rating (as a Lightroom export does),
    /// and indexing it as an asset keeps Photos' value — none, or 0 — rather
    /// than the file's. Reading the file's rating is for file photos (C3).
    @Test func cameraRatingFilesOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexSidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try MetadataFixture.lightroomJPEG(in: folder)
        #expect(try String(decoding: Data(contentsOf: url), as: UTF8.self).contains("xmp:Rating=\"\(MetadataFixture.rating)\""))

        guard case .success(let exif) = ExifReader.readExif(fromImageAt: url) else {
            Issue.record("fixture did not parse")
            return
        }
        let unrated = AssetInfo(assetId: "A", mediaType: 1, isFavorite: false, rating: nil)
        #expect(composer.compose(asset: unrated, exif: exif, exifStatus: .indexed).rating == nil)
        let zero = AssetInfo(assetId: "B", mediaType: 1, isFavorite: false, rating: 0)
        #expect(composer.compose(asset: zero, exif: exif, exifStatus: .indexed).rating == 0)
    }
}
