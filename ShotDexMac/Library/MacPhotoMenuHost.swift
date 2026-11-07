import Photos
import SwiftUI

/// What the photo menu (`MacPhotoMenu`) asks of the window: Move to Trash
/// runs the delete flow with its prompts (FS-19.04, the same gate as a smart
/// album's Delete), and New Album asks for a name.
struct MacPhotoMenuHost: ViewModifier {
    let menu: MacPhotoMenu
    let library: LibraryModel?
    /// Read again when a star, flag or favorite changes (the inspector).
    var selection: MacSelectionModel?

    @Environment(MacDependencies.self) private var dependencies
    @State private var deletion = PhotoDeletionFlow()
    @State private var sourceDeletion: DeletionTargetQueries.Request?
    @State private var deleteError: String?
    @State private var albumName = ""
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.undoManager) private var undoManager
    /// The plan of a Move to Trash is being read: a second one waits for it.
    @State private var isReadingPlan = false
    /// Hidden or unhidden while this window was behind: reload when it comes forward.
    @State private var missedHiddenChange = false

    func body(content: Content) -> some View {
        @Bindable var menu = menu
        content
            .photoDeletionPrompts(deletion)
            .sourceDeletion($sourceDeletion, context: dependencies.sourceDeletion) { removed, _ in
                library?.removeDeleted(ids: removed)
            }
            .alert(String(localized: "Couldn't Delete", comment: "Mac: a delete failed"),
                   isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button(String(localized: "OK", comment: "Delete: dismiss"), role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .alert(String(localized: "New Album", comment: "Mac: name a new album, title"),
                   isPresented: Binding(get: { menu.albumRequest != nil }, set: { if !$0 { menu.albumRequest = nil } }),
                   presenting: menu.albumRequest) { request in
                TextField(String(localized: "Album Name", comment: "Mac: new album name field"), text: $albumName)
                Button(String(localized: "Cancel", comment: "Mac: new album, dismiss"), role: .cancel) { albumName = "" }
                Button(String(localized: "Create", comment: "Mac: new album, create it")) {
                    let name = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
                    albumName = ""
                    menu.createAlbum(named: name, ids: request.ids)
                }
                .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { request in
                Text(request.photosCount == 0
                     ? String(localized: "The album is made in Photos.", comment: "Mac: new empty album")
                     : request.photosCount == 1
                     ? String(localized: "The selected photo goes into a new album in Photos.", comment: "Mac: new album with one photo")
                     : String(localized: "\(request.photosCount) selected photos go into a new album in Photos.",
                              comment: "Mac: new album with the selection; only photos in Photos go in (plural)"))
            }
            .alert(String(localized: "Couldn’t Finish", comment: "Mac photo menu: an action failed, title"),
                   isPresented: Binding(get: { menu.failure != nil }, set: { if !$0 { menu.failure = nil } })) {
                Button(String(localized: "OK", comment: "Mac photo menu: dismiss"), role: .cancel) {}
            } message: {
                Text(menu.failure ?? "")
            }
            .confirmationDialog(hideTitle(menu.hideRequest),
                                isPresented: Binding(get: { menu.hideRequest != nil }, set: { if !$0 { menu.hideRequest = nil } }),
                                presenting: menu.hideRequest) { request in
                // The safe choice first and on Return: Hide in ShotDex Only changes nothing in Photos.
                ForEach(request.commands.sorted { $0 == .hideInShotDexOnly && $1 != .hideInShotDexOnly }, id: \.title) { command in
                    if command == .hideInShotDexOnly {
                        Button(command.title) { menu.hide(command, ids: request.ids, touchesPhotos: request.touchesPhotos, undoManager: undoManager) }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(command.title) { menu.hide(command, ids: request.ids, touchesPhotos: request.touchesPhotos, undoManager: undoManager) }
                    }
                }
                Button(String(localized: "Cancel", comment: "Mac hide: dismiss"), role: .cancel) {}
            } message: { request in
                Text(request.commands.count > 1
                     ? String(localized: "Hidden photos leave All Photos, albums and search; unhide them in Collections › Hidden. Hide in Photos also puts their Photos copies in the Hidden album of the Photos app, on every device; to bring those back, use the Photos app.",
                              comment: "Mac hide: photos both in Photos and elsewhere")
                     : request.touchesPhotos
                     ? String(localized: "Hidden photos leave All Photos, albums and search; unhide them in Collections › Hidden. Photos items also go to the Hidden album of the Photos app, on every device; to bring them back there, use the Photos app.",
                              comment: "Mac hide: photos only in Photos")
                     : String(localized: "Hidden photos leave All Photos, albums and search; unhide them in Collections › Hidden. Their files are not changed.",
                              comment: "Mac hide: photos only in folders or on servers"))
            }
            // One model serves every window: the front one reloads it; the
            // rebuilt grid drops the hidden photos from its own selection.
            .onReceive(NotificationCenter.default.publisher(for: .macHiddenChanged)) { _ in
                guard appearsActive else { missedHiddenChange = true; return }
                library?.reload()
            }
            .onChange(of: appearsActive) { _, isActive in
                guard isActive, missedHiddenChange else { return }
                missedHiddenChange = false
                library?.reload()
            }
            .onChange(of: menu.trashRequest) { _, ids in
                guard let ids else { return }
                menu.trashRequest = nil
                delete(ids)
            }
            .task(id: dependencies.photoLibrary.assetChangeToken) { await menu.loadAlbums() }
            .onChange(of: menu.marksGeneration) { selection?.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .macGetInfo)) { note in
                // Every library window hears ⌘I: the front one answers.
                guard let selection, appearsActive else { return }
                // ⌘I shows and hides; the photo menu's Get Info only shows.
                MacInfoPanel.toggle(dependencies: dependencies, selection: selection, menu: menu, picture: MacRootWindow.demoPicture,
                                    onlyShows: note.object as? String == "show")
            }
            // Nothing on screen (a filter or place with no photos): nothing selected.
            .onChange(of: library?.items.isEmpty == true) { _, isEmpty in if isEmpty { selection?.set([]) } }
    }

    private func hideTitle(_ request: MacHideRequest?) -> String {
        let count = request?.ids.count ?? 0
        return count == 1 ? String(localized: "Hide 1 Photo?", comment: "Mac hide: confirm, one photo")
                          : String(localized: "Hide \(count) Photos?", comment: "Mac hide: confirm, several photos")
    }

    /// Folder and server photos have no PHAsset: PhotoKit alone would drop
    /// them and report success (FS-19.04 §2), so their plan is read first —
    /// off the main actor.
    private func delete(_ ids: [String]) {
        guard let library, !deletion.isChecking, !isReadingPlan else { NSSound.beep(); return }
        let database = dependencies.database, roots = dependencies.folderRoots
        isReadingPlan = true
        Task {
            defer { isReadingPlan = false }
            // A failed read must not fall through to the PhotoKit-only path,
            // which would drop folder and server copies and call it done.
            let read = await Task.detached(priority: .userInitiated) {
                Result { try DeletionTargetQueries(database: database, hasTrash: { roots.hasTrash($0) })
                    .request(photoIds: ids, selection: .photos) }
            }.value
            let request: DeletionTargetQueries.Request?
            switch read {
            case .success(let found): request = found
            case .failure(let error):
                deleteError = error.localizedDescription
                return
            }
            if let request {
                sourceDeletion = request
                return
            }
            #if DEBUG
            // The demo's photos are rows, not Photos assets: never ask PhotoKit to delete.
            if MacDemoLibrary.isOn { NSSound.beep(); return }
            #endif
            deletion.delete(ids, gate: dependencies.photoDeletionGate, perform: { targets in
                try await library.deleteAssets(ids: Set(targets), checkingServer: false)
            }, finished: { result in
                switch result {
                case .success, .failure(is CancellationError): break
                case .failure(let error):
                    if (error as? PHPhotosError)?.code != .userCancelled { deleteError = error.localizedDescription }
                }
            })
        }
    }
}

/// The host once the window has made its menu.
struct MacPhotoMenuHostIfReady: ViewModifier {
    let menu: MacPhotoMenu?
    let library: LibraryModel?
    let selection: MacSelectionModel?

    func body(content: Content) -> some View {
        if let menu {
            content.modifier(MacPhotoMenuHost(menu: menu, library: library, selection: selection))
        } else {
            content
        }
    }
}
