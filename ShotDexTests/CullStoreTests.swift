import Foundation
import Testing
@testable import ShotDex

@MainActor
struct CullStoreTests {

    private func makeStore() throws -> CullStore {
        CullStore(database: try AppDatabase.makeEmpty())
    }

    @Test func unwrittenAssetReadsAsUntouched() throws {
        let store = try makeStore()
        let state = try store.state(assetId: "a")
        #expect(state.rating == 0)
        #expect(state.flag == .unflagged)
        #expect(state.isEmpty)
        #expect(try store.culledCount() == 0)
    }

    @Test func ratingAndFlagAreStoredSeparately() throws {
        let store = try makeStore()
        try store.setRating(4, ids: ["a"])
        try store.setFlag(.picked, ids: ["a"])

        let state = try store.state(assetId: "a")
        #expect(state.rating == 4)
        #expect(state.flag == .picked)
    }

    /// Setting one must not blank the other — the whole reason this is a
    /// read-modify-write rather than an insert.
    @Test func settingFlagKeepsRating() throws {
        let store = try makeStore()
        try store.setRating(3, ids: ["a"])
        try store.setFlag(.rejected, ids: ["a"])
        try store.setFlag(.unflagged, ids: ["a"])

        #expect(try store.state(assetId: "a").rating == 3)
    }

    /// Back to untouched means no row, so the table's count answers "how much of
    /// this library has been culled".
    @Test func clearingBothRemovesTheRow() throws {
        let store = try makeStore()
        try store.setRating(5, ids: ["a"])
        try store.setFlag(.picked, ids: ["a"])
        #expect(try store.culledCount() == 1)

        try store.setRating(0, ids: ["a"])
        try store.setFlag(.unflagged, ids: ["a"])
        #expect(try store.culledCount() == 0)
        #expect(try store.state(assetId: "a").isEmpty)
    }

    @Test func ratingIsClampedToTheScale() throws {
        let store = try makeStore()
        try store.setRating(9, ids: ["a"])
        try store.setRating(-4, ids: ["b"])

        #expect(try store.state(assetId: "a").rating == 5)
        // -4 clamps to 0, which is untouched, so there is no row at all.
        #expect(try store.state(assetId: "b").isEmpty)
    }

    @Test func writesApplyToEveryPickedAsset() throws {
        let store = try makeStore()
        try store.setFlag(.picked, ids: ["a", "b", "c"])

        let states = try store.states(assetIds: ["a", "b", "c", "d"])
        #expect(states.count == 3)
        #expect(states["a"]?.flag == .picked)
        #expect(states["c"]?.flag == .picked)
        #expect(states["d"] == nil)
    }

    @Test func deletingAssetsDropsTheirCulling() throws {
        let store = try makeStore()
        try store.setRating(2, ids: ["a", "b"])
        try store.deleteAssets(ids: ["a"])

        #expect(try store.state(assetId: "a").isEmpty)
        #expect(try store.state(assetId: "b").rating == 2)
    }

    @Test func emptyIdListsAreNoOps() throws {
        let store = try makeStore()
        try store.setRating(3, ids: [])
        try store.setFlag(.picked, ids: [])
        try store.deleteAssets(ids: [])
        #expect(try store.states(assetIds: []).isEmpty)
        #expect(try store.culledCount() == 0)
    }
}
