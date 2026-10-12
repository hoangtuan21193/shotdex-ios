import Foundation
import Observation
import Photos

/// What opens the frame picker: a burst, and the frame to show first.
struct BurstFramesRequest: Identifiable, Equatable {
    var id: String { burstId }
    let burstId: String
    var startFrameId: String?
}

/// The frame picker's model (FS-02.05): loads one burst's frames, holds
/// which are kept, and sends the rest to Recently Deleted in **one** system
/// deletion — whose own dialog is the only confirmation.
@MainActor
@Observable
final class BurstFramesModel {
    enum Phase: Equatable { case loading, ready, empty }

    private(set) var selection = BurstSelection(frames: [])
    private(set) var phase: Phase = .loading
    private(set) var isDeleting = false
    /// Under `.limited` the app sees only the frames the user shared, and
    /// cannot know how many the burst really has (§7).
    let isLimited: Bool

    @ObservationIgnored let request: BurstFramesRequest
    @ObservationIgnored private let library: any BurstLibrary
    @ObservationIgnored private let deleteAssets: ([String]) async throws -> Void
    @ObservationIgnored private let banner: AppBannerModel?

    init(
        request: BurstFramesRequest,
        library: any BurstLibrary,
        isLimited: Bool,
        banner: AppBannerModel?,
        deleteAssets: @escaping ([String]) async throws -> Void
    ) {
        self.request = request
        self.library = library
        self.isLimited = isLimited
        self.banner = banner
        self.deleteAssets = deleteAssets
    }

    func load() async {
        let frames = await library.frames(ofBurst: request.burstId)
        selection = BurstSelection(frames: frames)
        if let start = request.startFrameId { selection.show(id: start) }
        phase = frames.count >= 2 ? .ready : .empty
    }

    func asset(for id: String) -> PHAsset? { library.asset(for: id) }

    func show(_ index: Int) { selection.show(index) }
    func toggleKeepCurrent() { selection.toggleKeepCurrent() }
    func keepOnlySuggested() { selection.keepOnlySuggested() }
    func keepOnly(_ id: String) { selection.keepOnly(id) }

    func next() { selection.show(selection.currentIndex + 1) }
    func previous() { selection.show(selection.currentIndex - 1) }

    /// `ShotDex can see 3 frames of this burst. …`
    var limitedNote: String? {
        guard isLimited else { return nil }
        return String(
            localized: "ShotDex can see \(selection.count) frames of this burst. Frames you haven't shared stay as they are.",
            comment: "Burst frame picker under limited photo access"
        )
    }

    enum Outcome: Equatable {
        case deleted(kept: [String])
        case cancelled
        case failed
    }

    /// Deletes every frame not kept (§6). Cancel in the system dialog or a
    /// failure changes nothing and keeps the ticks; a failure offers Try Again.
    func deleteUnkept() async -> Outcome {
        let ids = selection.deleteIds
        guard selection.canDelete, !isDeleting else { return .cancelled }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAssets(ids)
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return .cancelled
        } catch {
            banner?.show(Self.deleteFailed, actionTitle: MarkCopy.tryAgain) { [weak self] in
                Task { _ = await self?.deleteUnkept() }
            }
            return .failed
        }
        let kept = selection.frames.map(\.id).filter(selection.isKept)
        selection.remove(Set(ids))
        // No Undo: the app cannot read Recently Deleted.
        banner?.show(Self.moved(ids.count))
        return .deleted(kept: kept)
    }

    static func moved(_ count: Int) -> String {
        String(
            localized: "\(count) frames moved to Recently Deleted. Recover them in Photos within 30 days.",
            table: "Bursts",
            comment: "Banner after deleting the frames not kept (plural)"
        )
    }

    static var deleteFailed: String {
        String(localized: "Couldn't delete the frames.", comment: "Banner: the system deletion of burst frames failed; nothing was deleted")
    }
}
