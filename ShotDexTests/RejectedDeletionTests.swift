import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-01.12b AC-6 — Delete Rejected deletes the Rejected photos on screen,
/// and only those.
@MainActor
struct RejectedDeletionTests {

    /// Album X: 240 photos, 120 Rejected; 30 more Rejected outside X.
    static func fixture() async throws -> (PhotoMarks, PhotoMarksStore, album: [String]) {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let marks = PhotoMarks(store: store)
        let album = (0..<240).map { "x\($0)" }
        await marks.setFlag(.reject, ids: album.filter { Int($0.dropFirst())! % 2 == 0 })
        await marks.setFlag(.pick, ids: ["x1", "x3"])
        await marks.setFlag(.reject, ids: (0..<30).map { "other\($0)" })
        return (marks, store, album)
    }

    @Test func onlyVisibleRejected() async throws {
        let (marks, _, album) = try await Self.fixture()
        let ids = RejectedDeletion.ids(visible: album, flag: marks.flag(for:))

        #expect(ids.count == 120)
        #expect(ids.allSatisfy { $0.hasPrefix("x") })
        var criteria = FilterCriteria()
        #expect(!RejectedDeletion.showsPill(for: criteria))
        criteria.flags = [.rejected]
        #expect(RejectedDeletion.showsPill(for: criteria))
        #expect(MarkCopy.deletePill(120, locale: Locale(identifier: "en_US")) == "Delete 120")
    }

    /// AC-6 end to end below PhotoKit: the deletion gets exactly the 120 ids,
    /// their flag rows go (the live hook's job, done here by the fake), the
    /// 30 outside stay Rejected, and the banner says Recently Deleted.
    @Test func deletedRejectedRowsGone() async throws {
        let (marks, store, album) = try await Self.fixture()
        var asked: [[String]] = []
        let banner = AppBannerModel()
        let deleter = RejectedDeleter(deleteAssets: { ids in
            asked.append(ids)
            await marks.removeMarks(ids: ids)
        }, banner: banner)

        let outcome = await deleter.delete(RejectedDeletion.ids(visible: album, flag: marks.flag(for:)))

        #expect(outcome == .deleted(120))
        #expect(asked.count == 1 && asked[0].count == 120)
        #expect(try store.allFlags().filter { $0.value == .reject }.count == 30)
        #expect(marks.assetIds(flagged: .reject).allSatisfy { $0.hasPrefix("other") })
        #expect(banner.current?.text == MarkCopy.movedToRecentlyDeleted(120))
        #expect(banner.current?.actionTitle == nil)
        #expect(MarkCopy.movedToRecentlyDeleted(120, locale: Locale(identifier: "en_US"))
            == "120 photos moved to Recently Deleted. Recover them in Photos within 30 days.")
    }
}
