import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.02 §8: the Mac inspector's summary of a selection.
struct SelectionSummaryQueriesTests {
    private func row(_ id: String, date: Int, file: String, camera: String?, iso: Int, aperture: Double,
                     size: Int, isVideo: Bool = false) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: date, modificationDate: nil, mediaType: isVideo ? 2 : 1,
            cameraManufacturer: nil, cameraModel: camera, normalizedCameraModel: camera, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: "FE 85mm F1.8", normalizedLensModel: "FE 85mm F1.8", originalFilename: file,
            iso: iso, aperture: aperture, shutterSpeedSeconds: 0.004, shutterSpeedDisplay: "1/250", focalLength: 85,
            focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil, sensorFormat: nil,
            cropFactor: nil, width: 10, height: 10, fileSize: size, latitude: nil, longitude: nil, isFavorite: id == "a",
            indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
        )
    }

    @Test func rangesCountsKeywordsAndMarksOfTheSelectedPhotosOnly() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            row("a", date: 1_000, file: "A.ARW", camera: "ILCE-7M4", iso: 400, aperture: 1.8, size: 100),
            row("b", date: 3_000, file: "B.HEIC", camera: "ILCE-7M4", iso: 3200, aperture: 8, size: 50),
            row("c", date: 2_000, file: "C.JPG", camera: "X-T5", iso: 100, aperture: 2, size: 25),
            row("d", date: 9_000, file: "D.MOV", camera: "X-T5", iso: 12800, aperture: 1.4, size: 999, isVideo: true),
        ], cursorAssetId: nil)
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO pending_photo_rating (assetId, rating, ratedAt) VALUES ('a', 4, 1), ('b', 2, 1)")
            try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES ('a', 'pick', 1), ('c', 'reject', 1)")
            try db.execute(sql: """
                INSERT INTO photo_keyword (assetId, keyword, caseKey, foldKey) VALUES
                ('a', 'Kyoto', 'kyoto', 'kyoto'), ('b', 'kyoto', 'kyoto', 'kyoto'), ('b', 'temple', 'temple', 'temple'),
                ('d', 'night', 'night', 'night')
                """)
        }

        let summary = try await SelectionSummaryQueries(database: database).summary(ids: ["a", "b", "c"])

        #expect(summary.count == 3)
        #expect(summary.videoCount == 0)
        #expect(summary.firstDate == Date(timeIntervalSince1970: 1_000))
        #expect(summary.lastDate == Date(timeIntervalSince1970: 3_000))
        #expect(summary.totalBytes == 175)
        #expect(summary.formats.map(\.name).sorted() == ["HEIC", "JPG", "RAW"])
        #expect(summary.cameras == [.init(name: "ILCE-7M4", count: 2), .init(name: "X-T5", count: 1)])
        #expect(summary.iso == 100...3200)
        #expect(summary.aperture == 1.8...8)
        #expect(summary.keywords.first?.count == 2)
        #expect(summary.keywords.first?.name.lowercased() == "kyoto")
        #expect(summary.keywords.contains(.init(name: "temple", count: 1)))
        #expect(!summary.keywords.contains { $0.name == "night" })
        // c has no stars: 0 widens the range.
        #expect(summary.ratings == 0...4)
        #expect(summary.picks == 1)
        #expect(summary.rejects == 1)
        #expect(summary.favorites == 1)
        #expect(summary.sources == [.init(name: "Photos Library", kind: "photos", count: 3)])
    }

    /// More than one statement's worth (900 per read) adds up across reads.
    @Test func aSelectionLargerThanOneChunkCountsEveryPhoto() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<901).map { "p\($0)" }
        try MetadataStore(database: database).saveBatch(ids.map {
            row($0, date: 1_000, file: "\($0).JPG", camera: "X-T5", iso: 200, aperture: 2, size: 1)
        }, cursorAssetId: nil)
        let summary = try await SelectionSummaryQueries(database: database).summary(ids: ids)
        #expect(summary.count == 901)
        #expect(summary.totalBytes == 901)
        #expect(summary.cameras == [.init(name: "X-T5", count: 901)])
        #expect(summary.sources.first?.count == 901)
    }

    /// Ids the index does not hold (yet) give an empty summary, not a crash.
    @Test func photosNotInTheIndexGiveAnEmptySummary() async throws {
        let database = try AppDatabase.makeEmpty()
        let summary = try await SelectionSummaryQueries(database: database).summary(ids: ["gone"])
        #expect(summary.count == 0)
        #expect(summary.ratings == nil)
        #expect(summary.sources.isEmpty)
    }

    /// A chip per case, named as most of the photos spell it; words that only
    /// fold alike (accents) stay apart — a remove matches by case.
    @Test func keywordChipsGoByCaseAndTheCommonSpelling() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(["a", "b", "c"].map {
            row($0, date: 1_000, file: "\($0).JPG", camera: nil, iso: 100, aperture: 2, size: 1)
        }, cursorAssetId: nil)
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO photo_keyword (assetId, keyword, caseKey, foldKey) VALUES
                ('a', 'kyoto', 'kyoto', 'kyoto'), ('b', 'kyoto', 'kyoto', 'kyoto'), ('c', 'Kyoto', 'kyoto', 'kyoto'),
                ('a', 'Đà Lạt', 'đà lạt', 'da lat'), ('b', 'Da Lat', 'da lat', 'da lat')
                """)
        }
        let summary = try await SelectionSummaryQueries(database: database).summary(ids: ["a", "b", "c"])
        #expect(summary.keywords.first == .init(name: "kyoto", count: 3))
        #expect(summary.keywords.contains(.init(name: "Đà Lạt", count: 1)))
        #expect(summary.keywords.contains(.init(name: "Da Lat", count: 1)))
    }
}
