import Photos
import Testing
@testable import ShotDex

/// Compare's commands against real flags (in-memory `PhotoMarksStore`) and a
/// counted deletion (FS-01.08c §5–§6).
@MainActor
struct CompareModelTests {

    private final class DeletionLog {
        var asked: [[String]] = []
        var error: Error?
    }

    private func makeModel(
        ids: [String] = ["a", "b", "c"],
        log: DeletionLog = DeletionLog(),
        duplicateGroup: [String]? = nil
    ) throws -> (CompareModel, PhotoMarks) {
        let marks = PhotoMarks(store: PhotoMarksStore(database: try AppDatabase.makeEmpty()))
        let deleter = RejectedDeleter(
            deleteAssets: { ids in
                log.asked.append(ids)
                if let error = log.error { throw error }
            },
            banner: nil
        )
        let model = CompareModel(
            session: CompareSession(selection: ids)!,
            marks: marks,
            deleter: deleter,
            assets: [:],
            metadata: [:],
            duplicateGroup: duplicateGroup
        )
        return (model, marks)
    }

    /// AC-2: `X` on the working frame sets the real Reject flag.
    @Test func xOnTheWorkingFrameRejectsItForReal() async throws {
        let (model, marks) = try makeModel()
        model.session.setWorking("b")
        await model.apply(.flag(.reject))
        #expect(marks.flag(for: "b") == .reject)
        #expect(model.rejectedIds == ["b"])
        #expect(model.deleteTitle == "Delete 1 Photo")
    }

    /// AC-22: no Reject — a dimmed `Delete` that does nothing.
    @Test func noRejectsMeansADisabledDelete() async throws {
        let log = DeletionLog()
        let (model, _) = try makeModel(log: log)
        #expect(model.deleteTitle == "Delete")
        #expect(!model.canDelete)
        let result = await model.deleteRejected()
        #expect(result.next == nil)
        #expect(log.asked.isEmpty)
    }

    /// AC-8: Keep Only This gives Delete 3.
    @Test func keepOnlyGivesDeleteThree() async throws {
        let (model, marks) = try makeModel(ids: ["a", "b", "c", "d"])
        await model.keepOnly("b")
        #expect(model.rejectedIds == ["a", "c", "d"])
        #expect(marks.flag(for: "b") == nil)
    }

    /// AC-11: Cancel in the system dialog changes nothing.
    @Test func cancelInTheSystemDialogKeepsFramesAndFlags() async throws {
        let log = DeletionLog()
        log.error = PHPhotosError(.userCancelled)
        let (model, marks) = try makeModel(log: log)
        await model.setFlag(.reject, for: "c")
        let result = await model.deleteRejected()
        #expect(result.outcome == .cancelled)
        #expect(result.next == nil)
        #expect(model.session.ids == ["a", "b", "c"])
        #expect(marks.flag(for: "c") == .reject)
    }

    /// AC-9: only this comparison's Rejected photos go, and two left stay.
    @Test func deletedFramesLeaveAndOnlyThisComparisonsRejectsGo() async throws {
        let log = DeletionLog()
        let (model, marks) = try makeModel(ids: ["a", "b", "c", "d"], log: log)
        _ = await marks.setFlag(.reject, ids: ["elsewhere"])
        await model.setFlag(.reject, for: "b")
        await model.setFlag(.reject, for: "c")
        var gone: Set<String> = []
        model.onDeleted = { gone = $0 }
        let result = await model.deleteRejected()
        #expect(log.asked == [["b", "c"]])
        #expect(result.next == .stay)
        #expect(model.session.ids == ["a", "d"])
        #expect(gone == ["b", "c"])
    }

    /// AC-15: the last photo of a Duplicates group cannot take Reject.
    @Test func theGroupsLastPhotoRefusesReject() async throws {
        let (model, marks) = try makeModel(ids: ["a", "b"], duplicateGroup: ["a", "b"])
        await model.setFlag(.reject, for: "a")
        await model.setFlag(.reject, for: "b")
        #expect(marks.flag(for: "b") == nil)
        #expect(model.blockedMessage == "Keep at least one photo in this group.")
        #expect(!model.canReject("b"))
    }
}
