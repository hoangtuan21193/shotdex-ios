import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-01.12b AC-7 — Cancel in the system's dialog, or a failed deletion,
/// changes nothing.
@MainActor
struct RejectedDeletionCancelTests {

    /// AC-7: Cancel → 0 photos gone, all 120 still Rejected, no banner.
    @Test func cancelChangesNothing() async throws {
        let (marks, store, album) = try await RejectedDeletionTests.fixture()
        let banner = AppBannerModel()
        let deleter = RejectedDeleter(deleteAssets: { _ in
            throw PHPhotosError(.userCancelled)
        }, banner: banner)

        let outcome = await deleter.delete(RejectedDeletion.ids(visible: album, flag: marks.flag(for:)))

        #expect(outcome == .cancelled)
        #expect(try store.allFlags().filter { $0.value == .reject }.count == 150)
        #expect(banner.current == nil)
    }

    /// A deletion that fails: nothing gone, the flags stay, and the banner
    /// offers the same batch again (NF-04).
    @Test func failureOffersTryAgain() async throws {
        let (marks, store, album) = try await RejectedDeletionTests.fixture()
        let banner = AppBannerModel()
        var attempts = 0
        let deleter = RejectedDeleter(deleteAssets: { _ in
            attempts += 1
            throw CocoaError(.fileWriteUnknown)
        }, banner: banner)

        #expect(await deleter.delete(RejectedDeletion.ids(visible: album, flag: marks.flag(for:))) == .failed)
        #expect(attempts == 1)
        #expect(try store.allFlags().filter { $0.value == .reject }.count == 150)
        #expect(banner.current?.text == MarkCopy.deleteFailed)
        #expect(banner.current?.actionTitle == MarkCopy.tryAgain)
    }
}
