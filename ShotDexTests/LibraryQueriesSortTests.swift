import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.05 §5.1 — the Library's File Size orders, over data set (S) of the
/// spec's AC table: A 48 MB, B and C 3 MB on the same day (C's id sorts
/// after B's), D a 210 MB video, E and F with no known size.
struct LibraryQueriesSortTests {

    private static let day: TimeInterval = 86_400

    private func record(
        _ assetId: String, size: Int?, creation: Int, kind: MediaKind = .photo
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: creation,
            modificationDate: creation,
            mediaType: kind.storedValue,
            cameraManufacturer: nil,
            cameraModel: nil,
            normalizedCameraModel: nil,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: nil,
            iso: nil,
            aperture: nil,
            shutterSpeedSeconds: nil,
            shutterSpeedDisplay: nil,
            focalLength: nil,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: size,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private static func date(_ text: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return Int(formatter.date(from: text)!.timeIntervalSince1970)
    }

    /// Data set (S), saved in an order that matches none of the expected ones.
    private func makeQueries() throws -> LibraryQueries {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            record("F", size: nil, creation: Self.date("2026-02-02")),
            record("C", size: 3_000_000, creation: Self.date("2026-05-01")),
            record("A", size: 48_000_000, creation: Self.date("2026-01-03")),
            record("E", size: nil, creation: Self.date("2026-06-10")),
            record("D", size: 210_000_000, creation: Self.date("2025-12-24"), kind: .video),
            record("B", size: 3_000_000, creation: Self.date("2026-05-01")),
        ], cursorAssetId: nil)
        return LibraryQueries(database: database)
    }

    // AC-S1
    @Test func fileSizeLargest() async throws {
        let ids = try await makeQueries().gridItems(matching: FilterCriteria(), sort: .fileSizeLargest).map(\.assetId)
        #expect(ids == ["D", "A", "B", "C", "E", "F"])
    }

    // AC-S2 — unknown sizes still last, and B before C on the id tie-break.
    @Test func fileSizeSmallest() async throws {
        let ids = try await makeQueries().gridItems(matching: FilterCriteria(), sort: .fileSizeSmallest).map(\.assetId)
        #expect(ids == ["B", "C", "A", "D", "E", "F"])
    }

    // AC-S1, AC-S2 — equal sizes fall back to the newer capture date before
    // the id: Y's id sorts first but Z is newer, so Z leads in both orders.
    @Test func equalSizesPreferNewerDate() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            record("Y", size: 5_000_000, creation: Self.date("2026-01-01")),
            record("Z", size: 5_000_000, creation: Self.date("2026-03-01")),
        ], cursorAssetId: nil)
        let queries = LibraryQueries(database: database)
        for sort in [SortOption.fileSizeLargest, .fileSizeSmallest] {
            #expect(try await queries.gridItems(matching: FilterCriteria(), sort: sort).map(\.assetId) == ["Z", "Y"])
        }
    }

    // AC-S5
    @Test func menuOffersFileSize() {
        #expect(SortOption.menuOrders.count == 6)
        #expect(Array(SortOption.menuOrders.suffix(2)) == [.fileSizeLargest, .fileSizeSmallest])
        #expect(SortOption.fileSizeLargest.photoKitSortKey == nil)
        #expect(SortOption.fileSizeSmallest.photoKitSortKey == nil)
    }
}
