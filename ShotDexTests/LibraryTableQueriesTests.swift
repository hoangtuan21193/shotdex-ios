import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.02 §3: the list view's extra columns, read in one go.
struct LibraryTableQueriesTests {
    private func row(_ id: String, camera: String?, lens: String?) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: 1_700_000_000, modificationDate: nil, mediaType: 1,
            cameraManufacturer: nil, cameraModel: camera, normalizedCameraModel: camera, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: lens, normalizedLensModel: lens, originalFilename: "\(id).ARW",
            iso: 100, aperture: 2, shutterSpeedSeconds: 0.01, shutterSpeedDisplay: "1/100", focalLength: 35,
            focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil, sensorFormat: nil,
            cropFactor: nil, width: 10, height: 10, fileSize: 1, latitude: nil, longitude: nil, isFavorite: false,
            indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
        )
    }

    @Test func cameraLensSourceAndThePendingRatingWin() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([row("a", camera: "ILCE-7M4", lens: "FE 35mm F1.4 GM"),
                                                          row("b", camera: nil, lens: nil)], cursorAssetId: nil)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET rating = 2 WHERE assetId = 'a'")
            try db.execute(sql: "INSERT INTO pending_photo_rating (assetId, rating, ratedAt) VALUES ('a', 4, 1)")
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('b', 'reject', 1)")
            try db.execute(sql: "UPDATE photo_metadata SET isFavorite = 1 WHERE assetId = 'a'")
        }
        let details = try await LibraryTableQueries(database: database).details()
        #expect(details["a"]?.camera == "ILCE-7M4")
        #expect(details["a"]?.lens == "FE 35mm F1.4 GM")
        #expect(details["a"]?.rating == 4)
        #expect(details["a"]?.sourceName == "Photos Library")
        #expect(details["a"]?.sourceKind == "photos")
        #expect(details["b"]?.camera == nil)
        #expect(details["b"]?.rating == 0)
        #expect(details["a"]?.isFavorite == true)
        #expect(details["b"]?.isFavorite == false)
        #expect(details["b"]?.flag == .reject)
        #expect(details["a"]?.flag == nil)
    }

    @Test func detailsOfSomePhotosReadOnlyThose() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([row("a", camera: "X-T5", lens: nil), row("b", camera: "X-T5", lens: nil)],
                                                        cursorAssetId: nil)
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('b', 'pick', 1)")
        }
        let details = try await LibraryTableQueries(database: database).details(ids: ["b"])
        #expect(details.keys.sorted() == ["b"])
        #expect(details["b"]?.flag == .pick)
        #expect(details["b"]?.sourceName == "Photos Library")
    }
}
