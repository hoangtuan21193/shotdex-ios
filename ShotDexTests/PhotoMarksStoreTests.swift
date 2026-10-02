import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.12 — the flag and pending-rating tables, and the in-memory index
/// that writes them.
@MainActor
struct PhotoMarksStoreTests {

    static func record(_ id: String, rating: Int? = nil, favorite: Bool = false, created: Int = 1_700_000_000) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id,
            creationDate: created,
            modificationDate: created,
            mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: "Sony",
            cameraModel: "ILCE-7M4",
            normalizedCameraModel: "A7 IV",
            normalizedCameraManufacturer: "Sony",
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            iso: 400,
            aperture: 2.8,
            shutterSpeedSeconds: 0.004,
            shutterSpeedDisplay: "1/250",
            focalLength: 35,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: 35,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: 12_000_000,
            latitude: nil,
            longitude: nil,
            isFavorite: favorite,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue,
            rating: rating
        )
    }

    static func ids(matching filter: RatingFilter, in database: AppDatabase) async throws -> Set<String> {
        var criteria = FilterCriteria()
        criteria.ratingFilter = filter
        return Set(try await LibraryQueries(database: database)
            .gridItems(matching: criteria, sort: .dateTakenNewest).map(\.assetId))
    }

    static func metadataRow(_ id: String, in database: AppDatabase) throws -> Row? {
        try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM photo_metadata WHERE assetId = ?", arguments: [id])
        }
    }

    @Test func migrationCreatesTablesAndColumn() throws {
        let database = try AppDatabase.makeEmpty()
        try database.reader.read { db in
            #expect(try db.tableExists("photo_flag"))
            #expect(try db.tableExists("pending_photo_rating"))
            let columns = try db.columns(in: "photo_metadata").map(\.name)
            #expect(columns.contains("rating"))
            #expect(try db.indexes(on: "photo_metadata").contains { $0.name == "photo_metadata_rating" })
        }
    }

    /// AC-1, first half: iOS 26.5, `4` on A writes exactly one pending row
    /// A = 4, and the indexed row is untouched column by column.
    @Test func pendingRowOnly() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch([Self.record("A"), Self.record("B")], cursorAssetId: nil)
        let before = try Self.metadataRow("A", in: database)

        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        await marks.setRating(4, ids: ["A"])

        let rows = try PhotoMarksStore(database: database).pendingRatingRows()
        #expect(rows.map(\.assetId) == ["A"])
        #expect(rows.first?.rating == 4)
        #expect(try Self.metadataRow("A", in: database) == before)
        #expect(marks.rating(for: "A") == 4)
    }

    /// AC-1, second half: Clear local metadata index and a fresh index run
    /// leave the star in place — the filter still finds A.
    @Test func clearIndexKeepsMarks() async throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        try metadata.saveBatch([Self.record("A"), Self.record("B")], cursorAssetId: nil)
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        await marks.setRating(4, ids: ["A"])
        await marks.setFlag(.reject, ids: ["B"])

        try metadata.deleteAll()
        #expect(try await Self.ids(matching: .atLeast(4), in: database).isEmpty)
        try metadata.saveBatch([Self.record("A"), Self.record("B")], cursorAssetId: nil)

        #expect(try await Self.ids(matching: .atLeast(4), in: database) == ["A"])
        #expect(try PhotoMarksStore(database: database).allFlags() == ["B": .reject])
    }

    /// The one rule for every iOS: a pending row wins over Photos' rating,
    /// and without one Photos' rating counts (NULL as 0).
    @Test func currentRatingIsPendingElsePhotos() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch([
            Self.record("photos5", rating: 5),
            Self.record("photos5pending2", rating: 5),
            Self.record("photosNil", rating: nil),
            Self.record("pending3", rating: nil),
            Self.record("photos2pending0", rating: 2),
        ], cursorAssetId: nil)
        let store = PhotoMarksStore(database: database)
        try store.setPendingRating(2, ids: ["photos5pending2"])
        try store.setPendingRating(3, ids: ["pending3"])
        try store.setPendingRating(0, ids: ["photos2pending0"])

        #expect(try await Self.ids(matching: .atLeast(3), in: database) == ["photos5", "pending3"])
        #expect(try await Self.ids(matching: .atLeast(1), in: database) == ["photos5", "photos5pending2", "pending3"])
        #expect(try await Self.ids(matching: .unrated, in: database) == ["photosNil", "photos2pending0"])
    }

    @Test func clearingStarsBelow27RemovesTheRow() async throws {
        let database = try AppDatabase.makeEmpty()
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        await marks.setRating(3, ids: ["A"])
        await marks.setRating(0, ids: ["A"])

        #expect(try PhotoMarksStore(database: database).pendingRatingCount() == 0)
        #expect(marks.rating(for: "A") == 0)
    }

    @Test func undoRestoresPreviousRating() async throws {
        let database = try AppDatabase.makeEmpty()
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        await marks.setRating(2, ids: ["A"])
        let change = await marks.setRating(5, ids: ["A", "B"])
        await marks.undo(change)

        #expect(marks.rating(for: "A") == 2)
        #expect(marks.rating(for: "B") == 0)
        #expect(try PhotoMarksStore(database: database).allPendingRatings() == ["A": 2])
    }

    @Test func reloadReadsWhatWasStored() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = PhotoMarksStore(database: database)
        try store.setPendingRating(4, ids: ["A"])
        try store.setFlag(.pick, ids: ["A", "B"])

        let marks = PhotoMarks(store: store)
        await marks.loadIfNeeded()

        #expect(marks.summary(for: "A") == PhotoMarkSummary(rating: 4, flag: .pick))
        #expect(marks.summary(for: "B") == PhotoMarkSummary(rating: 0, flag: .pick))
        #expect(marks.summary(for: "C").isEmpty)
    }
}

struct MarkKeyCommandTests {

    @Test func noClashWithViewerKeys() {
        let keys = MarkKeyCommand.bindings.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(Set(keys).isDisjoint(with: MarkKeyCommand.viewerKeys))
    }

    @Test func keysMapToActions() {
        #expect(MarkKeyCommand.action(for: "4") == .rate(4))
        #expect(MarkKeyCommand.action(for: "0") == .rate(0))
        #expect(MarkKeyCommand.action(for: "P") == .flag(.pick))
        #expect(MarkKeyCommand.action(for: "x") == .flag(.reject))
        #expect(MarkKeyCommand.action(for: "u") == .flag(nil))
        #expect(MarkKeyCommand.action(for: "f") == nil)
        #expect(MarkKeyCommand.action(for: "6") == nil)
    }
}
