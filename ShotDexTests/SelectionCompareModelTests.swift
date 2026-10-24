import Photos
import Testing
@testable import ShotDex

/// Compare from a selection (FS-01.08): marks that live only in the
/// comparison, and Delete N through a counted deletion.
@MainActor
struct SelectionCompareModelTests {

    private final class DeletionLog {
        var asked: [[String]] = []
        var error: Error?
    }

    private func makeModel(
        ids: [String] = ["a", "b", "c"],
        log: DeletionLog = DeletionLog(),
        sourceRequest: @escaping @MainActor ([String]) -> DeletionTargetQueries.Request? = { _ in nil }
    ) -> SelectionCompareModel {
        let deleter = RejectedDeleter(
            deleteAssets: { ids in
                log.asked.append(ids)
                if let error = log.error { throw error }
            },
            banner: nil
        )
        return SelectionCompareModel(ids: ids, assets: [:], metadata: [:], deleter: deleter, sourceRequest: sourceRequest)
    }

    @Test func requestNeedsTwoDifferentPhotos() {
        #expect(CompareRequest(selection: ["a"]) == nil)
        #expect(CompareRequest(selection: ["a", "a"]) == nil)
        #expect(CompareRequest(selection: ["b", "a", "b"])?.ids == ["b", "a"])
    }

    @Test func nothingMarkedMeansDeleteIsOff() {
        let model = makeModel()
        #expect(model.deletion?.isEnabled == false)
        #expect(model.deletion?.title == "Delete")
    }

    @Test func markingCountsInComparisonOrder() {
        let model = makeModel()
        model.setMarked(true, "c")
        model.setMarked(true, "a")
        #expect(model.markedIds == ["a", "c"])
        #expect(model.deletion?.title == "Delete 2")
        model.setMarked(false, "c")
        #expect(model.markedIds == ["a"])
    }

    @Test func deleteSendsTheMarkedPhotosAndDropsThem() async {
        let log = DeletionLog()
        let model = makeModel(ids: ["a", "b", "c"], log: log)
        model.setMarked(true, "b")
        await model.deleteMarked()
        #expect(log.asked == [["b"]])
        #expect(model.ids == ["a", "c"])
        #expect(model.markedIds.isEmpty)
    }

    /// Cancel in the system's dialog changes nothing; the marks stay.
    @Test func cancelledDeleteKeepsEverything() async {
        let log = DeletionLog()
        log.error = PHPhotosError(.userCancelled)
        let model = makeModel(log: log)
        model.setMarked(true, "a")
        await model.deleteMarked()
        #expect(model.ids == ["a", "b", "c"])
        #expect(model.markedIds == ["a"])
    }

    /// Deleting down to one photo leaves nothing to compare — the screen
    /// closes on fewer than two.
    @Test func deletingAllButOneLeavesFewerThanTwo() async {
        let model = makeModel(ids: ["a", "b"])
        model.setMarked(true, "b")
        await model.deleteMarked()
        #expect(model.ids == ["a"])
        #expect(model.ids.count < CompareSession.minimumCount)
    }

    /// A marked photo with a copy outside Photos goes to the ShotDex
    /// confirmation first; nothing is deleted from here.
    @Test func sourceCopiesWaitForTheShotDexConfirmation() async throws {
        let log = DeletionLog()
        let request = try #require(Self.sampleRequest())
        let model = makeModel(log: log, sourceRequest: { _ in request })
        model.setMarked(true, "a")
        await model.deleteMarked()
        #expect(log.asked.isEmpty)
        #expect(model.sourceRequest != nil)
        model.removeDeleted(["a"])
        #expect(model.ids == ["b", "c"])
    }

    private static func sampleRequest() -> DeletionTargetQueries.Request? {
        DeletionTargetQueries.Request(
            photoIds: ["a"], targets: [[]], photosOnly: [],
            plan: MixedDeletionPlan(photos: [[]], selection: .rejected)
        )
    }
}
