import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.12 — writing marks through `PhotoMarks`.
@MainActor
struct PhotoMarksTests {

    /// AC-6: A is a favorite with no flag. `P` then `X`: Picked, then
    /// Rejected and no longer Picked — favorite untouched at both steps.
    @Test func pickThenRejectReplaces() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            [PhotoMarksStoreTests.record("A", favorite: true)], cursorAssetId: nil
        )
        let store = PhotoMarksStore(database: database)
        let marks = PhotoMarks(store: store)

        await marks.setFlag(.pick, ids: ["A"])
        #expect(marks.flag(for: "A") == .pick)
        #expect(try store.allFlags() == ["A": .pick])

        await marks.setFlag(.reject, ids: ["A"])
        #expect(marks.flag(for: "A") == .reject)
        #expect(try store.allFlags() == ["A": .reject])
        #expect(marks.assetIds(flagged: .pick).isEmpty)
    }

    /// AC-6, the other half: the flag path has no way to reach favorite —
    /// `PhotoMarks` holds no favorite writer — and the indexed row (which
    /// mirrors Photos' favorite) is identical before and after.
    @Test func flagNeverTouchesFavorite() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            [PhotoMarksStoreTests.record("A", favorite: true)], cursorAssetId: nil
        )
        let before = try PhotoMarksStoreTests.metadataRow("A", in: database)
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))

        await marks.setFlag(.pick, ids: ["A"])
        await marks.setFlag(.reject, ids: ["A"])
        await marks.setFlag(nil, ids: ["A"])

        #expect(try PhotoMarksStoreTests.metadataRow("A", in: database) == before)
        #expect(try PhotoMarksStore(database: database).allFlags().isEmpty)
    }

    @Test func flagUndoRestoresEachPhoto() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = PhotoMarksStore(database: database)
        let marks = PhotoMarks(store: store)
        await marks.setFlag(.pick, ids: ["A"])

        let change = await marks.setFlag(.reject, ids: ["A", "B"])
        await marks.undo(change)

        #expect(marks.flag(for: "A") == .pick)
        #expect(marks.flag(for: "B") == nil)
        #expect(try store.allFlags() == ["A": .pick])
    }

    @Test func versionBumpsOnEveryChange() async throws {
        let marks = PhotoMarks(store: PhotoMarksStore(database: try AppDatabase.makeEmpty()))
        let start = marks.version
        await marks.setFlag(.pick, ids: ["A"])
        await marks.setRating(3, ids: ["A"])

        #expect(marks.version == start + 2)
    }

    // MARK: iOS 27 — stars in Photos (FS-01.12 AC-2)

    /// AC-2: 300 photos with no stars → Rating ★★★ → one block of 300
    /// requests; every photo reads back 3; no pending row; the filter column
    /// and the modification date follow the write.
    @Test func photosModeOneBlock300() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<300).map { "p\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.map { PhotoMarksStoreTests.record($0, created: 100) }, cursorAssetId: nil
        )
        let writer = FakePropertyWriter(modificationDate: 100)
        let store = PhotoMarksStore(database: database)
        try store.setPendingRating(2, ids: ["p7"])  // left over from before iOS 27
        let marks = PhotoMarks(store: store, metadataStore: MetadataStore(database: database), ratingWriter: writer)
        await marks.loadIfNeeded()

        await marks.setRating(3, ids: ids)

        #expect(writer.blocks == [300])
        #expect(ids.allSatisfy { writer.ratings[$0] == 3 && marks.rating(for: $0) == 3 })
        #expect(try store.pendingRatingCount() == 0)
        let rows: [[Int?]] = try await database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT rating, modificationDate FROM photo_metadata")
                .map { [$0["rating"] as Int?, $0["modificationDate"] as Int?] }
        }
        #expect(rows.allSatisfy { $0 == [3, 101] })
        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(3), in: database).count == 300)
    }

    /// The re-stamp only moves a row that still had the pre-write date: a row
    /// with an edit the index has not read keeps looking stale.
    @Test func restampLeavesUnreadEditsAlone() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.saveBatch([
            PhotoMarksStoreTests.record("same", created: 100),
            PhotoMarksStoreTests.record("edited", created: 50),
        ], cursorAssetId: nil)

        try store.recordRatingWrite(["same": 4, "edited": 4], result: PropertyWriteResult(dates: [
            "same": .init(before: 100, after: 101),
            "edited": .init(before: 100, after: 101),
        ]))

        let dates = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT assetId, modificationDate FROM photo_metadata ORDER BY assetId")
                .map { ($0["assetId"] as String, $0["modificationDate"] as Int?) }
        }
        #expect(dates.map(\.0) == ["edited", "same"])
        #expect(dates.map(\.1) == [50, 101])
    }

    @Test func photosModeUndoIsOneBlock() async throws {
        let writer = FakePropertyWriter(modificationDate: 100)
        let marks = PhotoMarks(
            store: PhotoMarksStore(database: try AppDatabase.makeEmpty()),
            ratingWriter: writer,
            readPhotosRatings: { ids in Dictionary(uniqueKeysWithValues: ids.map { ($0, $0 == "A" ? 2 : 0) }) }
        )
        let change = await marks.setRating(5, ids: ["A", "B"])
        await marks.undo(change)

        #expect(writer.blocks == [2, 2])
        #expect(writer.ratings == ["A": 2, "B": 0])
        #expect(marks.rating(for: "A") == 2)
    }
}

/// Counts blocks and requests the way PhotoKit would see them; moves each
/// asset's modification date by one second per write.
final class FakePropertyWriter: PhotoPropertyWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _blocks: [Int] = []
    private var _ratings: [String: Int] = [:]
    var failure: Error?
    let modificationDate: Int

    init(modificationDate: Int) { self.modificationDate = modificationDate }

    var blocks: [Int] { lock.withLock { _blocks } }
    var ratings: [String: Int] { lock.withLock { _ratings } }

    func setRatings(_ ratings: [String: Int]) async throws -> PropertyWriteResult {
        try lock.withLock {
            if let failure { throw failure }
            _blocks.append(ratings.count)
            _ratings.merge(ratings) { $1 }
        }
        return PropertyWriteResult(dates: ratings.mapValues { _ in
            .init(before: modificationDate, after: modificationDate + 1)
        })
    }
}
