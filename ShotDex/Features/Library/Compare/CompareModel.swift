import Foundation
import Observation
import Photos
import SwiftUI

/// What opens a comparison from a grid's selection: the photos, in the
/// order they were chosen (FS-01.08 §2).
struct CompareRequest: Identifiable {
    let id = UUID()
    let ids: [String]

    /// Nil below two photos — the Compare button is dimmed there, so this
    /// is the guard behind it.
    init?(selection: [String]) {
        var seen = Set<String>()
        let unique = selection.filter { seen.insert($0).inserted }
        guard unique.count >= CompareSession.minimumCount else { return nil }
        ids = unique
    }
}

/// A selection as a comparison (FS-01.08): the same two-pane screen as a
/// Duplicates group, with Delete N on its top bar. Marks live here only —
/// closing without Delete changes nothing in the library.
@MainActor
@Observable
final class SelectionCompareModel: PhotoCompareSource {
    private(set) var ids: [String]
    private(set) var marked: Set<String> = []
    /// A deletion that reaches a file or a server copy, waiting on the
    /// ShotDex confirmation (FS-19.04 §2).
    var sourceRequest: DeletionTargetQueries.Request?

    @ObservationIgnored private let assetsById: [String: PHAsset]
    @ObservationIgnored private let metadataById: [String: PhotoMetadata]
    @ObservationIgnored private let deleter: RejectedDeleter
    @ObservationIgnored private let sourceRequestFor: @MainActor ([String]) -> DeletionTargetQueries.Request?

    init(
        ids: [String],
        assets: [String: PHAsset],
        metadata: [String: PhotoMetadata],
        deleter: RejectedDeleter,
        sourceRequest: @escaping @MainActor ([String]) -> DeletionTargetQueries.Request? = { _ in nil }
    ) {
        self.ids = ids
        self.assetsById = assets
        self.metadataById = metadata
        self.deleter = deleter
        self.sourceRequestFor = sourceRequest
    }

    /// The app's model for a request: rows and assets read once for the
    /// compared photos only.
    static func live(request: CompareRequest, dependencies: AppDependencies) -> SelectionCompareModel {
        let ids = request.ids
        let rows = (try? dependencies.libraryQueries.metadata(assetIds: ids)) ?? [:]
        var assets: [String: PHAsset] = [:]
        for asset in PhotoLibraryService.fetchAssets(ids: ids) { assets[asset.localIdentifier] = asset }
        return SelectionCompareModel(
            ids: ids,
            assets: assets,
            metadata: rows,
            deleter: .live(photoLibrary: dependencies.photoLibrary, banner: dependencies.banner),
            sourceRequest: { ids in
                let roots = dependencies.folderRoots
                return try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
                    .request(photoIds: ids, selection: .rejected)
            }
        )
    }

    // MARK: PhotoCompareSource

    var title: String {
        String(localized: "Compare · \(ids.count) photos", comment: "Compare title: how many photos of the selection are compared")
    }

    var preferredA: String? { nil }
    func asset(for id: String) -> PHAsset? { assetsById[id] }

    func storedAspect(of id: String) -> CGFloat? {
        guard let row = metadataById[id], let width = row.width, let height = row.height, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    /// A selection has no scan to say how two photos differ.
    func differences(of id: String, comparedWith other: String) -> [String] { [] }

    func isMarked(_ id: String) -> Bool { marked.contains(id) }

    func setMarked(_ isMarked: Bool, _ id: String) {
        if isMarked { marked.insert(id) } else { marked.remove(id) }
    }

    /// The marked photos, in the comparison's order — what Delete N deletes.
    var markedIds: [String] { ids.filter(marked.contains) }

    var deletion: PhotoCompareDeletion? {
        let count = markedIds.count
        return PhotoCompareDeletion(
            title: count > 0
                ? String(localized: "Delete \(count)", comment: "Compare: delete the photos marked Delete")
                : String(localized: "Delete", comment: "Compare: delete, nothing marked yet"),
            isEnabled: count > 0,
            run: { [weak self] in await self?.deleteMarked() }
        )
    }

    // MARK: Deleting

    /// Deletes the marked photos through the system's own dialog, or hands a
    /// file or server copy to the ShotDex confirmation first. Cancel or a
    /// failure changes nothing; the marks stay.
    func deleteMarked() async {
        let ids = markedIds
        guard !ids.isEmpty else { return }
        if let request = sourceRequestFor(ids) {
            sourceRequest = request
            return
        }
        guard case .deleted = await deleter.delete(ids) else { return }
        removeDeleted(Set(ids))
    }

    /// The photos a deletion took out leave the comparison; fewer than two
    /// left closes it.
    func removeDeleted(_ gone: Set<String>) {
        guard !gone.isEmpty else { return }
        ids.removeAll(where: gone.contains)
        marked.subtract(gone)
    }
}

/// Opens Compare for a grid's selection — Library, an album, a smart album,
/// On This Day.
private struct SelectionCompare: ViewModifier {
    @Binding var request: CompareRequest?
    let onDismiss: () -> Void
    @Environment(AppDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $request, onDismiss: onDismiss) { request in
            SelectionCompareCover(model: .live(request: request, dependencies: dependencies), startId: request.ids[0])
        }
    }
}

private struct SelectionCompareCover: View {
    @State var model: SelectionCompareModel
    let startId: String

    var body: some View {
        PhotoCompareScreen(source: model, startId: startId)
            .sourceDeletion($model.sourceRequest) { removed, _ in model.removeDeleted(removed) }
    }
}

extension View {
    func selectionCompare(_ request: Binding<CompareRequest?>, onDismiss: @escaping () -> Void) -> some View {
        modifier(SelectionCompare(request: request, onDismiss: onDismiss))
    }
}
