import SwiftUI

/// The iOS app's `SourceDeletionContext`, read from the environment.
private struct AppSourceDeletion: ViewModifier {
    @Binding var request: DeletionTargetQueries.Request?
    let onFinished: (_ removed: Set<String>, DeletionService.Summary) -> Void
    @Environment(AppDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        let database = dependencies.database
        let roots = dependencies.folderRoots
        let banner = dependencies.banner
        content.sourceDeletion($request, context: SourceDeletionContext(
            makeService: { dependencies.makeDeletionService() },
            makeQueries: { DeletionTargetQueries(database: database, hasTrash: { roots.hasTrash($0) }) },
            showBanner: { banner.show($0) }
        ), onFinished: onFinished)
    }
}

extension View {
    /// Presents `request`'s confirmation and runs it through the sources.
    func sourceDeletion(_ request: Binding<DeletionTargetQueries.Request?>,
                        onFinished: @escaping (_ removed: Set<String>, DeletionService.Summary) -> Void) -> some View {
        modifier(AppSourceDeletion(request: request, onFinished: onFinished))
    }
}
