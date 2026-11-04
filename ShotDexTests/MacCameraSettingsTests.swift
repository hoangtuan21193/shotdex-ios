import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-79: Settings › Cameras lists every camera and fixes an unknown one in place.
@Suite struct MacCameraSettingsTests {
    private func row(_ id: String, model: String, format: SensorFormat?, focal: Double = 23) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: 1_700_000_000, modificationDate: 1_700_000_000, mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: nil, cameraModel: model, normalizedCameraModel: model, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil,
            iso: nil, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: focal, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: (format ?? .unknown).rawValue, cropFactor: format?.typicalCropFactor, width: 6000, height: 4000, fileSize: 1_000,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000, exifStatus: ExifStatus.indexed.rawValue)
    }

    /// 2 unknown cameras listed first; picking APS-C for one leaves 1 unknown, marks it Custom and
    /// turns its 23 mm into a 34.5 mm equivalent.
    @Test func pickFormatInPlace() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.upsert(row("a1", model: "Canon EOS R6", format: .fullFrame, focal: 50))
        try store.upsert(row("a2", model: "Canon EOS R6", format: .fullFrame, focal: 50))
        try store.upsert(row("b1", model: "Mystery X1", format: nil))
        try store.upsert(row("c1", model: "Odd Cam", format: nil))
        let queries = CameraDatabaseQueries(database: database)
        let before = try queries.cameras()
        #expect(before.prefix(2).allSatisfy { $0.origin == .unknown })
        #expect(before.last?.model == "Canon EOS R6" && before.last?.photoCount == 2 && before.last?.origin == .builtIn)
        #expect(try store.unknownCameraModels().count == 2)

        try store.applyCustomMapping(CustomCameraMapping(normalizedCameraModel: "Mystery X1", sensorFormat: SensorFormat.apsC.rawValue,
                                                         cropFactor: SensorFormat.apsC.typicalCropFactor))

        let after = try queries.cameras()
        let mystery = try #require(after.first { $0.model == "Mystery X1" })
        #expect(mystery.origin == .custom && mystery.format == .apsC && mystery.cropFactor == 1.5)
        #expect(try store.unknownCameraModels() == ["Odd Cam"])
        let equivalent = try database.reader.read { db in
            try Double.fetchOne(db, sql: "SELECT equivalentFocalLength FROM photo_metadata WHERE assetId = 'b1'")
        }
        #expect(equivalent == 34.5)
        #expect(CameraDatabaseQueries.filtered(after, filter: .needsFormat, search: "").map(\.model) == ["Odd Cam"])
        #expect(CameraDatabaseQueries.filtered(after, filter: .custom, search: "").map(\.model) == ["Mystery X1"])
        #expect(CameraDatabaseQueries.filtered(after, filter: .all, search: "canon").map(\.model) == ["Canon EOS R6"])
    }

    /// One Unknown photo does not hide the format the others carry; the crop comes with that format.
    @Test func dominantFormatWins() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.upsert(row("a1", model: "X-T5", format: .apsC))
        try store.upsert(row("a2", model: "X-T5", format: .apsC))
        try store.upsert(row("a3", model: "X-T5", format: nil))
        let camera = try #require(try CameraDatabaseQueries(database: database).cameras().first)
        #expect(camera.format == .apsC && camera.cropFactor == 1.5 && camera.origin == .builtIn && camera.photoCount == 3)
    }

    /// Reset gives each camera back what the bundled database says — Unknown and no
    /// equivalent when it knows nothing — not the hand-picked values under a "Built-in" label.
    @Test func resetGoesBackToBundled() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.upsert(row("b1", model: "Mystery X1", format: nil))
        try store.applyCustomMapping(CustomCameraMapping(normalizedCameraModel: "Mystery X1", sensorFormat: SensorFormat.apsC.rawValue,
                                                         cropFactor: 1.5))
        try store.resetCustomMappings(to: SensorLookup(records: []))
        let camera = try #require(try CameraDatabaseQueries(database: database).cameras().first)
        #expect(camera.origin == .unknown && camera.format == .unknown)
        let equivalent = try database.reader.read { db in
            try Double.fetchOne(db, sql: "SELECT equivalentFocalLength FROM photo_metadata WHERE assetId = 'b1'")
        }
        #expect(equivalent == nil)
    }

    /// A mapping whose photos are not indexed (yet) is still listed, so Reset can reach it.
    @Test func mappingWithoutPhotosIsListed() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveCustomMapping(CustomCameraMapping(normalizedCameraModel: "Ghost", sensorFormat: "APS-C", cropFactor: 1.5))
        let cameras = try CameraDatabaseQueries(database: database).cameras()
        #expect(cameras.map(\.model) == ["Ghost"] && cameras.first?.origin == .custom && cameras.first?.photoCount == 0)
    }
}
