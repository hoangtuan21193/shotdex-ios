import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 AC-4 — a refused star migration changes nothing and is tried
/// again on the next launch, once.
@MainActor
struct RatingMigrationFailureTests {

    private typealias Pass = RatingMigrationPassTests

    /// AC-4: the block fails → every row stays (and still filters), no
    /// banner, no second try this launch; the next launch tries once more.
    @Test func failureKeepsAllAndRetriesNextLaunch() async throws {
        let (store, metadata, writer, read) = try Pass.fixture(pendingCount: 40)
        writer.failure = CocoaError(.fileWriteUnknown)
        var banners: [Int] = []
        let launch1 = Pass.pass(store, metadata, writer, read)
        launch1.onMoved = { banners.append($0) }

        #expect(await launch1.runIfNeeded() == .failed)
        #expect(await launch1.runIfNeeded() == .notRun)
        #expect(try store.pendingRatingCount() == 40)
        #expect(banners.isEmpty)
        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(1), in: metadata.database).count == 40)

        writer.failure = nil
        let launch2 = Pass.pass(store, metadata, writer, read)
        #expect(await launch2.runIfNeeded() == .moved(40))
        #expect(writer.blocks == [40])
    }

    /// The pending rows still filter while they wait (FS-01.12 §5).
    @Test func pendingStillFilters() async throws {
        let (store, metadata, _, _) = try Pass.fixture(pendingCount: 5)
        try store.setPendingRating(5, ids: ["p0"])
        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(5), in: metadata.database) == ["p0"])
        #expect(try await PhotoMarksStoreTests.ids(matching: .atLeast(1), in: metadata.database).count == 5)
    }
}
