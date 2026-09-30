import SwiftUI

/// What a server photo command does once its originals are on this device
/// (FS-17.06 §3).
enum ServerPhotoCommand: Equatable {
    case edit
}

/// One command on server photos, from the tap to the last file deleted: the
/// fetch, then the tool it opens, then the clean-up (FS-17.06 §4).
@MainActor
final class ServerPhotoCommandRun: Identifiable {
    let id = UUID()
    let command: ServerPhotoCommand
    let fetch: ServerEditFetchModel

    init(command: ServerPhotoCommand, fetch: ServerEditFetchModel) {
        self.command = command
        self.fetch = fetch
    }

    var photos: [FetchedServerPhoto] { fetch.fetched }

    /// Deletes the originals brought down. Every way out of a command ends
    /// here: an export, a discard, a close with nothing edited.
    func discardCopies() {
        guard let directory = fetch.workDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Presents a command's fetch sheet, then what the command opens. One
/// modifier so the browser, the viewer and a Network tile run commands the
/// same way.
struct ServerPhotoCommandHost: ViewModifier {
    @Binding var run: ServerPhotoCommandRun?
    /// The sheet's item: nil the moment the sheet goes.
    @State private var fetching: ServerPhotoCommandRun?
    /// The same run, kept for `onDismiss`, which runs after the item is nil.
    @State private var pending: ServerPhotoCommandRun?
    @State private var editing: ServerPhotoCommandRun?
    /// The run whose tool is on screen, cleaned up when it closes.
    @State private var open: ServerPhotoCommandRun?

    func body(content: Content) -> some View {
        content
            .onChange(of: run?.id) { _, id in
                guard id != nil, let run else { return }
                pending = run
                fetching = run
                self.run = nil
            }
            .sheet(item: $fetching, onDismiss: afterFetch) { run in
                ServerEditFetchSheet(model: run.fetch)
            }
            .fullScreenCover(item: $editing, onDismiss: closeTool) { run in
                PhotoEditorScreen(serverPhotos: run.photos)
            }
    }

    private func afterFetch() {
        guard let finished = pending else { return }
        pending = nil
        guard finished.fetch.stage == .fetched, !finished.photos.isEmpty else {
            finished.discardCopies()
            return
        }
        open = finished
        switch finished.command {
        case .edit: editing = finished
        }
    }

    private func closeTool() {
        open?.discardCopies()
        open = nil
    }
}

extension View {
    func serverPhotoCommands(_ run: Binding<ServerPhotoCommandRun?>) -> some View {
        modifier(ServerPhotoCommandHost(run: run))
    }
}
