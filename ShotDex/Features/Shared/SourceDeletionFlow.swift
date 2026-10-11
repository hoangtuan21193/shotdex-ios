import Photos
import SwiftUI

/// The ShotDex confirmation and run of a deletion that reaches past Photos
/// (FS-19.04 §2): one alert naming where each photo goes, a second red one
/// for a volume with no Trash, then `DeletionService` — files to their
/// Trash, server copies hidden, the Photos part behind the system dialog.
/// Every screen that deletes a selection uses this one flow, so the words
/// and the order never differ between the grid, an album and the viewer.
struct SourceDeletionFlow: ViewModifier {
    @Binding var request: DeletionTargetQueries.Request?
    /// After the run: the ids no screen shows any more, and the summary.
    let onFinished: (_ removed: Set<String>, DeletionService.Summary) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @State private var permanent: DeletionTargetQueries.Request?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .alert(
                request?.plan.title ?? "",
                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                presenting: request
            ) { pending in
                Button("Cancel", role: .cancel) { request = nil }
                Button(pending.plan.confirmTitle, role: .destructive) {
                    request = nil
                    if pending.plan.needsPermanentConfirmation {
                        permanent = pending
                    } else {
                        run(pending)
                    }
                }
            } message: { pending in
                Text(pending.plan.message + "\n\n" + MixedDeletionPlan.footnote)
            }
            .alert(
                permanent?.plan.permanentTitle ?? "",
                isPresented: Binding(get: { permanent != nil }, set: { if !$0 { permanent = nil } }),
                presenting: permanent
            ) { pending in
                Button("Cancel", role: .cancel) { permanent = nil }
                Button(String(localized: "Delete Permanently", comment: "Deletion: second confirmation button for a volume with no Trash"), role: .destructive) {
                    permanent = nil
                    run(pending)
                }
            } message: { pending in
                Text(pending.plan.permanentMessage)
            }
            .alert(
                String(localized: "Couldn't Delete Photos", comment: "Deletion through sources: a file stayed"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text($0) }
    }

    private func run(_ pending: DeletionTargetQueries.Request) {
        let service = dependencies.makeDeletionService()
        let roots = dependencies.folderRoots
        let queries = DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
        let banner = dependencies.banner
        Task {
            do {
                let summary = try await service.run(pending.targets, alsoPhotos: pending.photosOnly)
                let shown = try queries.stillShown(photoIds: pending.photoIds)
                var removed = Set(pending.photoIds).subtracting(shown)
                // Photos items with no copy row: gone unless the dialog said Cancel.
                if summary.photosCancelled { removed.subtract(pending.photosOnly) }
                onFinished(removed, summary)
                if let reason = summary.failure {
                    failure = reason
                } else {
                    let text = summary.banner(trashName: pending.plan.trashName)
                    if !text.isEmpty { banner.show(text) }
                }
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

extension View {
    /// Presents `request`'s confirmation and runs it through the sources.
    func sourceDeletion(_ request: Binding<DeletionTargetQueries.Request?>,
                        onFinished: @escaping (_ removed: Set<String>, DeletionService.Summary) -> Void) -> some View {
        modifier(SourceDeletionFlow(request: request, onFinished: onFinished))
    }
}
