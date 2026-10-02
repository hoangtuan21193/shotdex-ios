import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 AC-8 — smart albums on stars and flags.
@MainActor
struct SmartAlbumMarksTests {

    /// "Best" = flag is Pick AND rating at least 4, matching 12. Reject one
    /// of them and reopen: 11 — the sheet's count and the grid agree.
    @Test func bestPicksAtLeastFour() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<20).map { "p\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) },
            cursorAssetId: nil
        )
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        let best = Array(ids.prefix(12))
        await marks.setFlag(.pick, ids: best + ["p12"])          // p12: Picked, 3★
        await marks.setRating(4, ids: Array(best.prefix(6)))
        await marks.setRating(5, ids: Array(best.suffix(6)) + ["p13"]) // p13: 5★, no flag
        await marks.setRating(3, ids: ["p12"])

        let album = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .flag, op: .isExactly, text: "pick"),
            SmartAlbumRule(field: .rating, op: .atLeast, number: 4),
        ])
        let queries = LibraryQueries(database: database)
        #expect(Set(try await queries.gridItems(matching: album, sort: .dateTakenNewest).map(\.assetId)) == Set(best))
        #expect(try await queries.count(matching: album) == 12)

        await marks.setFlag(.reject, ids: ["p3"])

        let after = try await queries.gridItems(matching: album, sort: .dateTakenNewest)
        #expect(after.count == 11)
        #expect(try await queries.count(matching: album) == after.count)
        #expect(!after.map(\.assetId).contains("p3"))
    }

    @Test func ratingOperatorsAndFlagNegation() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            (0...5).map { PhotoMarksStoreTests.record("r\($0)", created: 1_700_000_000 + $0) },
            cursorAssetId: nil
        )
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        for stars in 1...5 { await marks.setRating(stars, ids: ["r\(stars)"]) }
        await marks.setFlag(.reject, ids: ["r0", "r1"])
        let queries = LibraryQueries(database: database)

        func ids(_ rule: SmartAlbumRule) async throws -> Set<String> {
            Set(try await queries.gridItems(matching: SmartAlbumQuery(rules: [rule]), sort: .dateTakenNewest).map(\.assetId))
        }
        #expect(try await ids(SmartAlbumRule(field: .rating, op: .equalTo, number: 3)) == ["r3"])
        #expect(try await ids(SmartAlbumRule(field: .rating, op: .atMost, number: 1)) == ["r0", "r1"])
        #expect(try await ids(SmartAlbumRule(field: .flag, op: .isNot, text: "reject")) == ["r2", "r3", "r4", "r5"])
        #expect(try await ids(SmartAlbumRule(field: .flag, op: .isExactly, text: "unflagged")).count == 4)
        #expect(SmartAlbumRule(field: .rating, op: .atLeast, number: 4).compactDisplaySummary == "★ ≥ 4")
    }
}
