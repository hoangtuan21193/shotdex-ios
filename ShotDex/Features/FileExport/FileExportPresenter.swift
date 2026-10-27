import SwiftUI

/// An *Export…* asked for from a selection's ⋯ or the viewer's ⋯
/// (FS-03.07b §3); the root, or the viewer, presents it.
struct FileExportRequest: Identifiable, Equatable {
    let model: FileExportModel
    var id: UUID { model.id }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// `Export…` in a selection's ⋯, right under Resize (FS-03.07c §1 item 1).
/// Dims with nothing picked rather than disappearing.
struct FileExportSelectionRow: View {
    let ids: [String]
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Button {
            navigation.fileExportRequest = FileExportRequest(model: .make(assetIds: ids, dependencies: dependencies))
        } label: {
            PhotoCommand.export.label
        }
        .disabled(ids.isEmpty)
    }
}

extension View {
    /// Hosts the Export sheet for a request.
    func fileExportPresenter(_ request: Binding<FileExportRequest?>) -> some View {
        modifier(FileExportPresenter(request: request))
    }
}

private struct FileExportPresenter: ViewModifier {
    @Binding var request: FileExportRequest?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isDuoInner) private var isDuoInner

    func body(content: Content) -> some View {
        content.sheet(item: $request) { request in
            FileExportSheet(model: request.model, layout: layout)
        }
    }

    /// iPad (regular both ways) gets the two-column card of the Mac-style
    /// canvas; a phone — and the Duo's short inner screen — the Form.
    /// The inner display reports regular both ways, so it is named here: its
    /// 652pt form sheet cut the 700pt card at both edges.
    private var layout: FileExportSheet.Layout {
        if isDuoInner { return .form }
        return horizontalSizeClass == .regular && verticalSizeClass == .regular ? .card : .form
    }
}
