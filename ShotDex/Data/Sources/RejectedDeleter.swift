import Foundation
import Photos

/// Sends Rejected photos to Recently Deleted through the system's deletion,
/// whose own dialog is the only confirmation (FS-01.12b §3). One instance per
/// use; the deletion itself is injected so tests count what was asked.
@MainActor
struct RejectedDeleter {
    enum Outcome: Equatable {
        case deleted(Int)
        /// The user said Cancel in the system's dialog: nothing changed.
        case cancelled
        case failed
    }

    /// PhotoKit's all-or-nothing deletion of exactly these ids.
    let deleteAssets: ([String]) async throws -> Void
    let banner: AppBannerModel?

    func delete(_ ids: [String]) async -> Outcome {
        guard !ids.isEmpty else { return .cancelled }
        do {
            try await deleteAssets(ids)
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return .cancelled
        } catch {
            // Nothing was deleted (PhotoKit does the whole batch or none);
            // the flags stay. Say so and offer the same batch again (NF-04).
            banner?.show(MarkCopy.deleteFailed, actionTitle: MarkCopy.tryAgain) {
                Task { await delete(ids) }
            }
            return .failed
        }
        // No Undo: the app cannot read Recently Deleted.
        banner?.show(MarkCopy.movedToRecentlyDeleted(ids.count))
        return .deleted(ids.count)
    }
}

extension RejectedDeleter {
    /// The app's deleter: PhotoKit through `PhotoLibraryService`, whose
    /// deletion hook also removes the photos' flags and stars (FS-01.12 §4).
    static func live(photoLibrary: PhotoLibraryService, banner: AppBannerModel) -> RejectedDeleter {
        RejectedDeleter(
            deleteAssets: { ids in
                try await photoLibrary.deleteAssetsCheckingServer(PhotoLibraryService.fetchAssets(ids: ids))
            },
            banner: banner
        )
    }
}
