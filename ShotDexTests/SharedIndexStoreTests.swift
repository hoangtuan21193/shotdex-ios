import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The shared index tables: what this device read goes up once, what came
/// from another device never goes back up, and a newer read wins
/// (intent 2026-11-02-icloud-shared-index).
struct SharedIndexStoreTests {
    private let database: AppDatabase
    private let store: SharedIndexStore

    init() throws {
        database = try AppDatabase.makeEmpty()
        store = SharedIndexStore(database: database)
    }

    private let canon = RawExif(make: "Canon", model: "Canon EOS R6", lensModel: "RF85mm F1.2 L USM",
                                iso: 3200, fNumber: 1.2, exposureTimeSeconds: 1.0 / 250, focalLength: 85)

    @Test func rawExifRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(canon)
        #expect(try JSONDecoder().decode(RawExif.self, from: data) == canon)
    }

    @Test func aLocalReadIsQueuedOnceAndReadBack() throws {
        let record = SharedExifRecord(cloudIdentifier: "CLOUD-1", modificationDate: 1_700_000_000, exif: canon)
        try store.saveLocal([record])
        try store.saveLocal([record])

        #expect(try store.outbox(limit: 10) == [.init(recordType: SharedIndexStore.photoExifType, recordName: "CLOUD-1")])
        #expect(try store.exif(cloudIdentifiers: ["CLOUD-1", "CLOUD-2"]) == ["CLOUD-1": record])
    }

    /// Re-reading a library must not re-upload what is already up.
    @Test func anUnchangedReadIsNotQueuedAgainAfterPush() throws {
        let record = SharedExifRecord(cloudIdentifier: "CLOUD-1", modificationDate: 1, exif: canon)
        try store.saveLocal([record])
        try store.removeFromOutbox(try store.outbox(limit: 10))

        try store.saveLocal([record])
        #expect(try store.outboxCount() == 0)

        var edited = record
        edited.modificationDate = 2
        try store.saveLocal([edited])
        #expect(try store.outboxCount() == 1)
    }

    @Test func aRowFromAnotherDeviceIsNotQueued() throws {
        let written = try store.saveRemote([SharedExifRecord(cloudIdentifier: "CLOUD-1", modificationDate: 1, exif: canon)])
        #expect(written == 1)
        #expect(try store.outboxCount() == 0)
        #expect(try store.exif(cloudIdentifiers: ["CLOUD-1"])["CLOUD-1"]?.exif == canon)
    }

    /// An older answer from elsewhere must not replace a read of the edited photo.
    @Test func aNewerReadWinsOverAnOlderRemoteRow() throws {
        try store.saveLocal([SharedExifRecord(cloudIdentifier: "CLOUD-1", modificationDate: 20, exif: canon)])
        let written = try store.saveRemote([SharedExifRecord(cloudIdentifier: "CLOUD-1", modificationDate: 10, exif: .empty)])

        #expect(written == 0)
        #expect(try store.exif(cloudIdentifiers: ["CLOUD-1"])["CLOUD-1"]?.modificationDate == 20)
    }

    /// A geocoded cell goes up; a cell from another device fills this
    /// device's photos in it without asking the geocoder.
    @Test func placeCellsTravelBothWays() throws {
        try insertPhoto("A", cellKey: "10:20")
        let place = ResolvedPlace(name: "Shibuya Crossing", locality: "Tokyo", country: "Japan", countryCode: "JP")
        try PlaceStore(database: database).save(place, cellKey: "1:2", latitude: 35.659, longitude: 139.700, localeIdentifier: "en_US")

        #expect(try store.outbox(limit: 10) == [.init(recordType: SharedIndexStore.placeCellType, recordName: "1:2")])
        #expect(try store.placeCells(keys: ["1:2"]).first?.place.locality == "Tokyo")

        let remote = SharedPlaceCell(cellKey: "10:20", latitude: 10, longitude: 20, place: place,
                                     searchText: "shibuya tokyo japan", localeIdentifier: "en_US", resolvedAt: 5)
        #expect(try store.saveRemote([remote]) == 1)
        #expect(try PlaceStore(database: database).place(assetId: "A")?.locality == "Tokyo")
        // Already resolved here: the local answer stays.
        #expect(try store.saveRemote([remote]) == 0)
    }

    private func insertPhoto(_ id: String, cellKey: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO photo_metadata (assetId, mediaType, exifStatus, indexedAt, placeCellKey) VALUES (?, 1, 'indexed', 0, ?)",
                arguments: [id, cellKey]
            )
        }
    }
}
