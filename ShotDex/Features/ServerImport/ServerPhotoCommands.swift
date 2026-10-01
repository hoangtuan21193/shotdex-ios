import ImageIO
import ShotDexKit
import SwiftUI

/// What a server photo command does once its originals are on this device
/// (FS-17.06 §3).
enum ServerPhotoCommand: Equatable {
    case edit
    case share
    case copy
    /// The clipboard's look onto every photo, then straight to the export.
    case pasteEdits
    case resize
    /// One file made from all the photos, through the export sheet
    /// (FS-17.06 §5b).
    case collage
    case video
    case combine(CombinePurpose)
}

/// Share and Copy of server originals (FS-17.06 §3): what is handed to the
/// system, made from the copies on disk.
enum ServerPhotoHandoff {
    /// Every file of every photo — both halves of a RAW+JPEG pair — with GPS
    /// removed when Share leaves location out (Settings), written beside the
    /// copies so the share carries the real file names.
    static func shareFiles(for photos: [FetchedServerPhoto], includesLocation: Bool, in directory: URL) -> [URL] {
        let folder = directory.appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return photos.flatMap(\.files).map { fetched in
            guard !includesLocation else { return fetched.url }
            let url = folder.appendingPathComponent(fetched.file.name)
            // Still hands over the original when the rewrite fails (a RAF):
            // the RAW alert that replaces this is FS-08.06 plan task 18.
            return (try? MetadataRewriter.rewrite(fetched.url, to: url, level: .noLocation)) != nil ? url : fetched.url
        }
    }

    /// Paste Edits: the clipboard's look on each photo, starting from
    /// nothing — a server photo carries no recipe of its own.
    @MainActor
    static func pastedRecipes(for photos: [FetchedServerPhoto], clipboard: EditClipboard) -> [String: PhotoEditRecipe] {
        Dictionary(photos.map { ($0.id, clipboard.paste(onto: .identity)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Longest side a copy puts on the pasteboard: a 60 MP frame as a
    /// bitmap is 240 MB, more than a paste is ever worth.
    static let copyMaxPixelSize = 4096

    /// The photo as a bitmap for the pasteboard, orientation applied.
    static func pasteboardImage(for photo: FetchedServerPhoto) -> CGImage? {
        EmbeddedPreview.thumbnail(ofFileAt: photo.primaryURL, maxPixelSize: copyMaxPixelSize)?.image
    }
}

/// One command on server photos, from the tap to the last file deleted: the
/// fetch, then the tool it opens, then the clean-up (FS-17.06 §4).
@MainActor
final class ServerPhotoCommandRun: Identifiable {
    let id = UUID()
    let command: ServerPhotoCommand
    let server: FileServer
    /// The browse run's login, which an export to the original folder uses.
    let access: any RemoteFileAccess
    let fetch: ServerEditFetchModel
    /// Set when an export arrived everywhere; the browser then leaves
    /// selection, as it does after Import.
    private(set) var hasExported = false

    init(command: ServerPhotoCommand, server: FileServer, access: any RemoteFileAccess, fetch: ServerEditFetchModel) {
        self.command = command
        self.server = server
        self.access = access
        self.fetch = fetch
    }

    /// What an editor on these photos needs to export them.
    var exportContext: ServerExportContext? {
        fetch.workDirectory.map { directory in
            ServerExportContext(server: server, access: access, workDirectory: directory) { [weak self] in
                self?.hasExported = true
            }
        }
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
    @Environment(AppDependencies.self) private var dependencies
    @Binding var run: ServerPhotoCommandRun?
    /// After a tool closes, with whether an export arrived — the browser
    /// reloads the folder it may have written to.
    var onClosed: (_ exported: Bool) -> Void = { _ in }
    /// The sheet's item: nil the moment the sheet goes.
    @State private var fetching: ServerPhotoCommandRun?
    /// The same run, kept for `onDismiss`, which runs after the item is nil.
    @State private var pending: ServerPhotoCommandRun?
    @State private var editing: ServerPhotoCommandRun?
    /// The run whose tool is on screen, cleaned up when it closes.
    @State private var open: ServerPhotoCommandRun?
    /// Paste Edits and Resize go straight to the export sheet.
    @State private var exporting: ExportPresentation?
    /// The tools that make one file from all the photos (FS-17.06 §5b).
    @State private var collaging: ServerPhotoCommandRun?
    @State private var videoRun: ServerPhotoCommandRun?
    @State private var stacking: PhotoStackPresentation?
    @State private var panorama: PanoramaMergePresentation?

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
                PhotoEditorScreen(serverPhotos: run.photos, export: run.exportContext)
            }
            .fullScreenCover(item: $collaging, onDismiss: closeTool) { run in
                CollageScreen(serverPhotos: run.photos, export: run.exportContext)
            }
            .fullScreenCover(item: $videoRun, onDismiss: closeTool) { run in
                VideoStudioScreen(
                    assets: [], mode: .multiClip, onSaved: { _ in },
                    server: run.exportContext.map { ServerVideoStudioLaunch(photos: run.photos, export: $0) }
                )
            }
            .fullScreenCover(item: $stacking, onDismiss: closeTool) { presentation in
                PhotoStackScreen(presentation: presentation)
            }
            .fullScreenCover(item: $panorama, onDismiss: closeTool) { presentation in
                PanoramaMergeScreen(presentation: presentation)
            }
            .sheet(item: $exporting, onDismiss: closeTool) { presentation in
                ServerExportSheet(model: presentation.model) {
                    open?.exportContext?.onExported()
                    exporting = nil
                }
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
        case .edit:
            editing = finished
        case .share:
            let includesLocation = !MetadataLevel.sharingDefault().removesLocation
            let files = ServerPhotoHandoff.shareFiles(
                for: finished.photos, includesLocation: includesLocation,
                in: finished.fetch.workDirectory ?? FileManager.default.temporaryDirectory
            )
            PhotoShareSheet.present(items: files) { closeTool() }
        case .copy:
            if let photo = finished.photos.first, let image = ServerPhotoHandoff.pasteboardImage(for: photo) {
                UIPasteboard.general.image = UIImage(cgImage: image)
            }
            closeTool()
        case .pasteEdits:
            guard let context = finished.exportContext else { return closeTool() }
            let recipes = ServerPhotoHandoff.pastedRecipes(for: finished.photos, clipboard: dependencies.editClipboard)
            exporting = ExportPresentation(model: .make(
                photos: finished.photos, recipes: recipes, context: context, dependencies: dependencies
            ))
        case .collage:
            guard CollageTemplateCatalog.supportedCounts.contains(finished.photos.count) else { return closeTool() }
            collaging = finished
        case .video:
            videoRun = finished
        case .combine(let purpose):
            guard finished.photos.count >= CombinePurpose.minimumPhotoCount else { return closeTool() }
            switch purpose {
            case .focusStack, .hdr, .stackExposures:
                stacking = PhotoStackPresentation(serverPhotos: finished.photos, purpose: purpose, export: finished.exportContext)
            case .panorama:
                panorama = PanoramaMergePresentation(serverPhotos: finished.photos, export: finished.exportContext)
            }
        case .resize:
            guard let context = finished.exportContext else { return closeTool() }
            exporting = ExportPresentation(model: .make(
                photos: finished.photos, recipes: [:], context: context, dependencies: dependencies,
                resizePresets: ResizePreset.builtIns.filter { $0.kind != .original }
            ))
        }
    }

    private func closeTool() {
        let exported = open?.hasExported ?? false
        open?.discardCopies()
        open = nil
        onClosed(exported)
    }
}

extension View {
    func serverPhotoCommands(_ run: Binding<ServerPhotoCommandRun?>, onClosed: @escaping (_ exported: Bool) -> Void = { _ in }) -> some View {
        modifier(ServerPhotoCommandHost(run: run, onClosed: onClosed))
    }
}

/// The connection a server run came from and where its copies live — what
/// the editor's Export… needs (FS-17.06 §6).
struct ServerExportContext {
    let server: FileServer
    let access: any RemoteFileAccess
    let workDirectory: URL
    /// Called once everything arrived.
    var onExported: () -> Void = {}
}

private struct ExportPresentation: Identifiable {
    let model: ServerExportModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}
