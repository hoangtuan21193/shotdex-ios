import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 AC-9 — stars and flags go with the photo, never on the word of a
/// `.limited` fetch.
@MainActor
struct UserMarkRemovalPolicyTests {

    @Test func fullAccessIndexRunRemoves() {
        let changes = IndexRunChanges(changed: ["A"], deleted: ["B"], isFullWalk: false, accessIsFull: true)
        #expect(UserMarkRemovalPolicy.idsToRemove(after: changes) == ["B"])
    }

    @Test func limitedIndexRunKeeps() {
        // C left the shared set: a full walk under `.limited` no longer finds
        // it, exactly as if it were deleted.
        let changes = IndexRunChanges(changed: [], deleted: ["C"], isFullWalk: true, accessIsFull: false)
        #expect(UserMarkRemovalPolicy.idsToRemove(after: changes).isEmpty)
    }

    @Test func deletionFromTheAppAlwaysRemoves() {
        #expect(UserMarkRemovalPolicy.removesMarks(on: .deletedInApp))
        #expect(!UserMarkRemovalPolicy.removesMarks(on: .indexRun(accessIsFull: false)))
    }

    /// AC-9 end to end below the PhotoKit line: B (Rejected, full access) is
    /// reported deleted → its row goes and the Rejected count drops by one;
    /// C (Rejected) is reported gone by a `.limited` run → its row stays.
    @Test func indexDeletionRemovesRejected() async throws {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let marks = PhotoMarks(store: store)
        await marks.setFlag(.reject, ids: ["B", "C", "D"])
        await marks.setRating(4, ids: ["B"])

        for changes in [
            IndexRunChanges(changed: [], deleted: ["B"], isFullWalk: false, accessIsFull: true),
            IndexRunChanges(changed: [], deleted: ["C"], isFullWalk: true, accessIsFull: false),
        ] {
            await marks.removeMarks(ids: Array(UserMarkRemovalPolicy.idsToRemove(after: changes)))
        }

        #expect(try store.allFlags() == ["C": .reject, "D": .reject])
        #expect(try store.pendingRatingCount() == 0)
        #expect(marks.assetIds(flagged: .reject) == ["C", "D"])
    }
}
