import Foundation
import GRDB
import os
import Testing
@testable import ShotDex

/// FS-01.12 AC-11 — the shared "updated though the date did not move" path.
struct IndexRunChangesTests {

    @Test func skippedUpdatedIdsAreDelivered() {
        // B is in Photos' `updated` set with an unchanged modification date:
        // the diff skips its file, the run still reports it.
        let changes = IndexRunChanges.incremental(
            inserted: ["A"], updated: ["B", "C"], deleted: ["C", "D"], accessIsFull: true
        )

        #expect(changes.changed == ["A", "B"])
        #expect(changes.deleted == ["C", "D"])
        #expect(!changes.isFullWalk)
        #expect(changes.accessIsFull)
    }

    @Test func observersHearEveryRunInOrderAndNotEmptyOnes() async {
        let observers = IndexRunObservers()
        let heard = OSAllocatedUnfairLock<[String]>(initialState: [])
        observers.add { changes in heard.withLock { $0.append("first \(changes.isFullWalk)") } }
        observers.add { changes in heard.withLock { $0.append("second \(changes.accessIsFull)") } }

        await observers.deliver(IndexRunChanges(changed: [], deleted: [], isFullWalk: true, accessIsFull: true))
        await observers.deliver(IndexRunChanges(changed: ["A"], deleted: [], isFullWalk: true, accessIsFull: false))

        #expect(heard.withLock { $0 } == ["first true", "second false"])
    }
}

@MainActor
struct AssetFactsRefresherTests {

    /// AC-11: iOS 27, A's rating changed in Photos, its modification date did
    /// not. After the incremental run the ★ ≥ 4 filter finds A, and nothing
    /// read A's file — the refresher has no reader, only the asset facts.
    @Test func ratingChangedInPhotosReachesFilter() async throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.saveBatch([
            PhotoMarksStoreTests.record("A", rating: 1),
            PhotoMarksStoreTests.record("B", rating: 2),
        ], cursorAssetId: nil)
        let before = try PhotoMarksStoreTests.metadataRow("A", in: database)

        let reads = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let refresher = AssetFactsRefresher(metadataStore: store) { ids in
            reads.withLock { $0.append(ids.sorted()) }
            return ["A": AssetFacts(isFavorite: false, rating: 4)].filter { ids.contains($0.key) }
        }
        refresher.refresh(.incremental(inserted: [], updated: ["A"], deleted: [], accessIsFull: true))

        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(4), in: database) == ["A"])
        #expect(reads.withLock { $0 } == [["A"]])
        // Only the facts moved: modification date, EXIF status and every
        // EXIF column are what they were, so nothing was re-read.
        let after = try #require(try PhotoMarksStoreTests.metadataRow("A", in: database))
        let original = try #require(before)
        for column in original.columnNames where column != "rating" {
            #expect(after[column] as DatabaseValue == original[column] as DatabaseValue, "\(column)")
        }
    }

    @Test func deletedIdsAreNotRead() {
        let reads = OSAllocatedUnfairLock<[String]>(initialState: [])
        let refresher = AssetFactsRefresher(metadataStore: MetadataStore(database: try! AppDatabase.makeEmpty())) { ids in
            reads.withLock { $0.append(contentsOf: ids) }
            return [:]
        }
        refresher.refresh(IndexRunChanges(changed: ["A", "B"], deleted: ["B"], isFullWalk: false, accessIsFull: true))

        #expect(reads.withLock { $0 } == ["A"])
    }

    /// Below iOS 27 there is no Photos rating: the favorite still refreshes,
    /// the rating column is left alone.
    @Test func updateAssetFactsBatch() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.saveBatch([
            PhotoMarksStoreTests.record("A", rating: 3),
            PhotoMarksStoreTests.record("B", rating: nil, favorite: true),
        ], cursorAssetId: nil)

        try store.updateAssetFacts([
            "A": AssetFacts(isFavorite: true, rating: nil),
            "B": AssetFacts(isFavorite: false, rating: 5),
        ])

        let rows = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT assetId, isFavorite, rating FROM photo_metadata ORDER BY assetId")
        }
        #expect(rows.map { $0["isFavorite"] as Bool } == [true, false])
        #expect(rows.map { $0["rating"] as Int? } == [3, 5])
    }

    @Test func ratingBackfillOnlyNulls() throws {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        try store.saveBatch([
            PhotoMarksStoreTests.record("A", rating: 3),
            PhotoMarksStoreTests.record("B", rating: nil),
        ], cursorAssetId: nil)

        #expect(try store.assetIdsMissingRating(limit: 10) == ["B"])
        try store.fillRatings(["A": 0, "B": 2])

        #expect(try store.assetIdsMissingRating(limit: 10).isEmpty)
        let ratings = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT rating FROM photo_metadata ORDER BY assetId").map { $0["rating"] as Int? }
        }
        #expect(ratings == [3, 2])
    }
}
