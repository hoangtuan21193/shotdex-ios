import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 AC-5 — under `.limited` the star migration writes what it can see
/// and keeps every other row.
@MainActor
struct RatingMigrationLimitedTests {

    private typealias Pass = RatingMigrationPassTests

    private static func pending(_ count: Int) -> [PendingRating] {
        (0..<count).map { PendingRating(assetId: "p\($0)", rating: $0 % 5 + 1, ratedAt: 1_000) }
    }

    /// AC-5: `.limited` shows 200 of the 1,240 → 200 writes, 1,040 stay,
    /// nothing dropped as "deleted".
    @Test func limitedWritesVisibleOnly() {
        let rows = Self.pending(1_240)
        let photos = Dictionary(uniqueKeysWithValues: rows.prefix(200).map { ($0.assetId, 0) })

        let plan = RatingMigrationPlan.make(pending: rows, photosRatings: photos, accessIsFull: false)

        #expect(plan.writes.count == 200)
        #expect(plan.kept.count == 1_040)
        #expect(plan.droppedAsDeleted.isEmpty)
        #expect(plan.rowsToDelete.count == 200)
    }

    /// AC-5 through the pass: `.limited` writes what it can see.
    @Test func limitedKeepsTheRest() async throws {
        let (store, metadata, writer, read) = try Pass.fixture(pendingCount: 50, visible: 10)
        let pass = Pass.pass(store, metadata, writer, read, full: false)

        #expect(await pass.runIfNeeded() == .moved(10))
        #expect(writer.blocks == [10])
        #expect(try store.pendingRatingCount() == 40)
    }
}
