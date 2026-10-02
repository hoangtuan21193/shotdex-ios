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
}
