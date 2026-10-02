import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 §5 — pending stars into Photos on the first iOS 27 launch.
struct RatingMigrationPlanTests {

    private static func pending(_ count: Int) -> [PendingRating] {
        (0..<count).map { PendingRating(assetId: "p\($0)", rating: $0 % 5 + 1, ratedAt: 1_000) }
    }

    /// AC-3: 1,240 rows; 5 photos deleted; 3 already rated in Photos →
    /// 1,232 writes, the 3 keep Photos' rating, all 1,240 rows go.
    @Test func twelveFortyCase() {
        let rows = Self.pending(1_240)
        var photos: [String: Int] = [:]
        for row in rows.dropFirst(5) { photos[row.assetId] = 0 }
        for row in rows.suffix(3) { photos[row.assetId] = 4 }

        let plan = RatingMigrationPlan.make(pending: rows, photosRatings: photos, accessIsFull: true)

        #expect(plan.writes.count == 1_232)
        #expect(plan.droppedForPhotos.count == 3)
        #expect(plan.droppedAsDeleted.count == 5)
        #expect(plan.kept.isEmpty)
        #expect(Set(plan.rowsToDelete).count == 1_240)
        #expect(rows.suffix(3).allSatisfy { plan.writes[$0.assetId] == nil })
        #expect(plan.writes["p5"] == 1)
    }
}

@MainActor
struct RatingMigrationPassTests {

    static func fixture(pendingCount: Int, visible: Int? = nil) throws -> (PhotoMarksStore, MetadataStore, FakePropertyWriter, @Sendable ([String]) -> [String: Int]) {
        let database = try AppDatabase.makeEmpty()
        let store = PhotoMarksStore(database: database)
        let ids = (0..<pendingCount).map { "p\($0)" }
        try MetadataStore(database: database).saveBatch(ids.map { PhotoMarksStoreTests.record($0, created: 100) }, cursorAssetId: nil)
        try store.setPendingRating(3, ids: ids, at: Date(timeIntervalSince1970: 1_000))
        let shown = Set(ids.prefix(visible ?? pendingCount))
        let read: @Sendable ([String]) -> [String: Int] = { asked in
            Dictionary(uniqueKeysWithValues: asked.filter(shown.contains).map { ($0, 0) })
        }
        return (store, MetadataStore(database: database), FakePropertyWriter(modificationDate: 100), read)
    }

    static func pass(_ store: PhotoMarksStore, _ metadata: MetadataStore, _ writer: FakePropertyWriter,
                             _ read: @escaping @Sendable ([String]) -> [String: Int], full: Bool = true) -> RatingMigrationPass {
        RatingMigrationPass(store: store, metadataStore: metadata, writer: writer, readPhotosRatings: read,
                            accessIsFull: { full }, now: { Date(timeIntervalSince1970: 2_000) })
    }

    /// AC-3: one block; the banner once — a second launch finds nothing.
    @Test func bannerOnce() async throws {
        let (store, metadata, writer, read) = try Self.fixture(pendingCount: 40)
        var banners: [Int] = []
        for _ in 0..<2 {
            let pass = Self.pass(store, metadata, writer, read)
            pass.onMoved = { banners.append($0) }
            await pass.runIfNeeded()
        }
        #expect(writer.blocks == [40])
        #expect(banners == [40])
        #expect(try store.pendingRatingCount() == 0)
        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(3), in: metadata.database).count == 40)
        #expect(MarkCopy.movedRatings(1_232, locale: Locale(identifier: "en_US")) == "Moved 1,232 star ratings to Photos.")
        #expect(MarkCopy.movedRatings(1, locale: Locale(identifier: "en_US")) == "Moved 1 star rating to Photos.")
    }

    /// A star set again while the write was in flight survives the cleanup.
    @Test func starSetDuringTheMoveSurvives() async throws {
        let (store, metadata, writer, read) = try Self.fixture(pendingCount: 2)
        try store.setPendingRating(5, ids: ["p1"], at: Date(timeIntervalSince1970: 3_000))
        await Self.pass(store, metadata, writer, read).runIfNeeded()

        #expect(try store.allPendingRatings() == ["p1": 5])
    }

    @Test func belowIOS27NothingRuns() async throws {
        let (store, metadata, _, read) = try Self.fixture(pendingCount: 3)
        let pass = RatingMigrationPass(store: store, metadataStore: metadata, writer: nil, readPhotosRatings: read, accessIsFull: { true })
        #expect(await pass.runIfNeeded() == .notRun)
        #expect(try store.pendingRatingCount() == 3)
    }
}
