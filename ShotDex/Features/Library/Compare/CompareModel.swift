import Foundation
import Observation
import Photos
import UIKit

/// What opens a comparison: the photos, in the order they were chosen, and
/// where the viewer underneath starts (FS-01.08c §7).
struct CompareRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    /// The viewer's page for the Select photo, so Single lands on it.
    let startIndex: Int
    /// Told which photos a Delete N removed — Duplicates prunes its groups.
    var onDeleted: ((Set<String>) -> Void)?

    /// From a selection. Nil below two photos — the Compare button is dimmed
    /// there, so this is the guard behind it.
    @MainActor
    init?(selection: [String], source: any PhotoBrowsingSource) {
        guard let session = CompareSession(selection: selection) else { return nil }
        ids = session.ids
        startIndex = source.index(of: session.selectId) ?? 0
    }
}

/// One comparison inside the viewer: the session (who is Select, which
/// candidate, which frame is being worked on), the photos' rows, and the
/// two commands that change the library — flags and Delete N.
///
/// Flags are **real** (FS-01.12): written through `PhotoMarks`, seen by the
/// grid, Cull and the Rejected filter at once, and still there after the
/// viewer closes. Nothing here keeps a mark of its own.
@MainActor
@Observable
final class CompareModel {
    var session: CompareSession
    /// The zoom the frames are at; 1 is Fit.
    private(set) var zoomScale: CGFloat = 1
    private(set) var isDeleting = false

    @ObservationIgnored let sync = CompareScrollSynchronizer()
    @ObservationIgnored private(set) var assetsById: [String: PHAsset]
    @ObservationIgnored private(set) var metadataById: [String: PhotoMetadata]
    @ObservationIgnored private var namesById: [String: String] = [:]
    @ObservationIgnored private let marks: PhotoMarks?
    @ObservationIgnored private let deleter: RejectedDeleter
    /// The deletion through the photos' sources when any Rejected one has a
    /// copy outside Photos (FS-19.04 §2); nil keeps the PhotoKit path.
    @ObservationIgnored private let sourceRequest: @MainActor ([String]) -> DeletionTargetQueries.Request?
    /// Told which photos a Delete N removed — Duplicates prunes its groups.
    @ObservationIgnored var onDeleted: ((Set<String>) -> Void)?
    /// What the last Delete N removed, until the host has read it.
    @ObservationIgnored private var lastDeletion: Set<String>?

    init(
        session: CompareSession,
        marks: PhotoMarks?,
        deleter: RejectedDeleter,
        assets: [String: PHAsset],
        metadata: [String: PhotoMetadata],
        sourceRequest: @escaping @MainActor ([String]) -> DeletionTargetQueries.Request? = { _ in nil }
    ) {
        self.session = session
        self.marks = marks
        self.deleter = deleter
        self.sourceRequest = sourceRequest
        self.assetsById = assets
        self.metadataById = metadata
        sync.onZoomChange = { [weak self] scale in self?.zoomScale = scale }
    }

    /// The app's model for a request: rows and assets read once for the
    /// compared photos only.
    static func live(request: CompareRequest, dependencies: AppDependencies, marks: PhotoMarks?) -> CompareModel? {
        live(session: CompareSession(selection: request.ids),
             dependencies: dependencies, marks: marks)
    }

    static func live(
        session: CompareSession?,
        dependencies: AppDependencies,
        marks: PhotoMarks?
    ) -> CompareModel? {
        guard let session else { return nil }
        let ids = session.ids
        let rows = (try? dependencies.libraryQueries.metadata(assetIds: ids)) ?? [:]
        var assets: [String: PHAsset] = [:]
        for asset in PhotoLibraryService.fetchAssets(ids: ids) { assets[asset.localIdentifier] = asset }
        return CompareModel(
            session: session,
            marks: marks,
            deleter: .live(photoLibrary: dependencies.photoLibrary, banner: dependencies.banner),
            assets: assets,
            metadata: rows,
            sourceRequest: { ids in
                let roots = dependencies.folderRoots
                return try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
                    .request(photoIds: ids, selection: .rejected)
            }
        )
    }

    // MARK: Reads

    func asset(for id: String) -> PHAsset? { assetsById[id] }

    func marks(for id: String) -> PhotoMarkSummary {
        guard let marks else { return PhotoMarkSummary(rating: 0, flag: nil) }
        _ = marks.version
        return marks.summary(for: id, photosRating: assetsById[id]?.photosStarRating)
    }

    func flag(for id: String) -> PhotoFlag? {
        guard let marks else { return nil }
        _ = marks.version
        return marks.flag(for: id)
    }

    /// The Rejected photos **in this comparison**, in its order — what
    /// Delete N deletes (§5, 12b §3).
    var rejectedIds: [String] {
        RejectedDeletion.ids(visible: session.ids, flag: flag(for:))
    }

    var pickedCount: Int { session.ids.filter { flag(for: $0) == .pick }.count }

    /// `Delete 2 Photos`, or `Delete` dimmed at none (§5, AC-22).
    var deleteTitle: String {
        let count = rejectedIds.count
        guard count > 0 else {
            return String(localized: "Delete", comment: "Compare: the delete button with no Rejected photo, dimmed")
        }
        return String(localized: "Delete \(count) Photos", table: MarkCopy.table, comment: "Compare: deletes every Rejected photo in the comparison (plural)")
    }

    var canDelete: Bool { !rejectedIds.isEmpty && !isDeleting }

    /// `1 picked · 1 rejected`, or nothing with no flags.
    var flagSummary: String? {
        let picked = pickedCount
        let rejected = rejectedIds.count
        guard picked + rejected > 0 else { return nil }
        return String(
            localized: "\(picked) picked · \(rejected) rejected",
            comment: "Compare: subtitle, how many compared photos are Picked and Rejected"
        )
    }

    func name(for id: String) -> String {
        if let cached = namesById[id] { return cached }
        let name = metadataById[id]?.originalFilename
            ?? assetsById[id].flatMap { PHAssetResource.assetResources(for: $0).first?.originalFilename }
            ?? String(localized: "Photo", comment: "Compare: a frame's name when the file name is unknown")
        namesById[id] = name
        return name
    }

    /// `Sony A7 IV · 35 mm · f/2.8 · 1/250 s · ISO 400`.
    func exifLine(for id: String) -> String? {
        guard let metadata = metadataById[id] else { return nil }
        return MetadataFormatter.metadataLine([
            metadata.normalizedCameraModel ?? metadata.cameraModel,
            metadata.focalLength.flatMap(MetadataFormatter.focalLength),
            metadata.aperture.flatMap(MetadataFormatter.aperture),
            metadata.shutterSpeedDisplay,
            metadata.iso.flatMap(MetadataFormatter.iso),
        ])
    }

    /// `Photo, DSC04513.ARW, No rating, Rejected, marked for deletion` (§8).
    func accessibilityLabel(for id: String) -> String {
        let summary = marks(for: id)
        let rating = summary.rating == 0
            ? String(localized: "No rating", comment: "VoiceOver: a compare frame with no stars")
            : MarkCopy.starsAccessibility(summary.rating)
        var parts = [String(localized: "Photo", comment: "VoiceOver: a compare frame"), name(for: id), rating]
        switch summary.flag {
        case .reject:
            parts.append(String(localized: "Rejected, marked for deletion", comment: "VoiceOver: a compare frame flagged Reject"))
        case .pick:
            parts.append(MarkCopy.flagWord(.pick))
        case nil:
            break
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Flags and stars

    func setFlag(_ flag: PhotoFlag?, for id: String) async {
        guard let marks else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = await marks.setFlag(flag, ids: [id])
    }

    func setRating(_ stars: Int, for id: String) async {
        guard let marks else { return }
        _ = await marks.setRating(stars, ids: [id], photosRatings: assetsById[id]?.photosStarRating.map { [id: $0] })
    }

    /// `0–5 P X U` on the working frame.
    func apply(_ action: MarkKeyAction) async {
        let id = session.workingId
        switch action {
        case .rate(let stars): await setRating(stars, for: id)
        case .flag(let flag): await setFlag(flag, for: id)
        }
    }

    /// Keep Only This (§5): Reject every other photo, take Reject off this
    /// one.
    func keepOnly(_ id: String) async {
        guard let marks else { return }
        let change = session.keepOnly(id, flag: flag(for:))
        if !change.reject.isEmpty { _ = await marks.setFlag(.reject, ids: change.reject) }
        if !change.unreject.isEmpty { _ = await marks.setFlag(nil, ids: change.unreject) }
    }

    // MARK: Delete N

    struct DeleteResult {
        let outcome: RejectedDeleter.Outcome
        let next: CompareSession.AfterDeletion?
        /// The Rejected photos reach a folder, a drive or a server: the
        /// ShotDex confirmation runs first (`SourceDeletionFlow`), then
        /// `removedThroughSources(_:)`.
        var sourceRequest: DeletionTargetQueries.Request?
    }

    /// Deletes the Rejected photos of this comparison through the system's
    /// own dialog — the only confirmation (§6) — then says where the viewer
    /// goes. Cancel or a failure changes nothing; the flags stay.
    func deleteRejected() async -> DeleteResult {
        let ids = rejectedIds
        guard !ids.isEmpty, !isDeleting else { return DeleteResult(outcome: .cancelled, next: nil) }
        if let request = sourceRequest(ids) {
            return DeleteResult(outcome: .cancelled, next: nil, sourceRequest: request)
        }
        isDeleting = true
        defer { isDeleting = false }
        let outcome = await deleter.delete(ids)
        guard case .deleted = outcome else { return DeleteResult(outcome: outcome, next: nil) }
        let gone = Set(ids)
        lastDeletion = gone
        onDeleted?(gone)
        let next = session.afterDeletion(gone: gone)
        return DeleteResult(outcome: outcome, next: next)
    }

    /// After the source deletion ran: the photos it took out leave the
    /// comparison the way a Photos deletion's do; Cancel removes none.
    func removedThroughSources(_ gone: Set<String>) -> CompareSession.AfterDeletion? {
        guard !gone.isEmpty else { return nil }
        lastDeletion = gone
        onDeleted?(gone)
        return session.afterDeletion(gone: gone)
    }

    /// The photos the last Delete N removed, once.
    func takeLastDeletion() -> Set<String>? {
        defer { lastDeletion = nil }
        return lastDeletion
    }

    // MARK: Zoom

    /// The photo's original size, for 100%.
    func pixelSize(for id: String) -> CGSize {
        if let asset = assetsById[id], asset.pixelWidth > 0, asset.pixelHeight > 0 {
            return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        }
        // A file photo: the size its EXIF gave the index.
        guard let row = metadataById[id], let width = row.width, let height = row.height, width > 0, height > 0 else { return .zero }
        return CGSize(width: width, height: height)
    }

    /// The farthest a frame may zoom: past 100% of the largest original, or
    /// the viewer's own 5×.
    func maximumZoom(box: CGSize, screenScale: CGFloat) -> CGFloat {
        let full = session.ids.map {
            CompareZoom.actualPixelsScale(pixelSize: pixelSize(for: $0), box: box, screenScale: screenScale)
        }.max() ?? 1
        return max(5, full * 2)
    }
}
