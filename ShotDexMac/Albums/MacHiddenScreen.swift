import Photos
import SwiftUI

/// Collections › Hidden (board `MAC_Hidden`, FS-19.04 §3): the photos
/// ShotDex hid — every copy hidden — in day sections, and Unhide for the
/// selection. Photos' own Hidden album is not here: an app cannot read it.
struct MacHiddenScreen: View {
    /// The sources, for the note's "still on “NAS Home”".
    let sources: [SourceStore.Source]
    let photoMenu: MacPhotoMenu?
    @Binding var showsInspector: Bool
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.undoManager) private var undoManager
    /// The last read failed: say so, never "No Hidden Photos".
    @State private var loadError: String?
    @State private var items: [LibraryGridItem] = []
    @State private var generation = 0
    @State private var hasLoaded = false
    @State private var selected: Set<String> = []
    @State private var selectionModel: MacSelectionModel?
    /// The sources the hidden copies are on.
    @State private var sourceNames: [String] = []
    @State private var isUnhiding = false
    @State private var failure: String?
    /// PhotoKit assets of the hidden photos, fetched with each load.
    @State private var assets = MacAssetMap()
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let loadError, items.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Couldn’t Load Hidden Photos", comment: "Mac Hidden: the read failed"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Hidden: read again"), action: reload)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasLoaded, items.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Hidden Photos", comment: "Mac Hidden: nothing hidden"), systemImage: "eye.slash")
                } description: {
                    Text("Photos you hide in ShotDex appear here until you unhide them. Photos you unhide go back to All Photos.",
                         comment: "Mac Hidden: empty, why")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasLoaded {
                note
                MacPhotoGrid(items: items, photoLibrary: dependencies.photoLibrary,
                             asset: { [assets] in assets.byId[$0] }, picture: MacRootWindow.demoPicture,
                             isNewestFirst: true, onSelection: { ids in
                                 selected = ids
                                 selectionModel?.set(ids)
                             },
                             contextMenu: photoMenu.map { menu in { menu.menu(for: $0, includesHide: false) } },
                             markKey: photoMenu.map { menu in { [selectionModel] in menu.markKey($0, ids: selectionModel?.ids ?? []) } },
                             generation: generation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            // As every Library place: the history arrows, not built yet.
            ToolbarItemGroup(placement: .navigation) {
                Button { } label: { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                    .disabled(true)
                Button { } label: { Label(String(localized: "Forward", comment: "Mac toolbar"), systemImage: "chevron.right") }
                    .disabled(true)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(MacPhotoMenu.shareServices, id: \.title) { service in
                        Button(service.menuItemTitle) { photoMenu?.share(Array(selected), with: service) }
                    }
                } label: {
                    Label(String(localized: "Share", comment: "Mac toolbar"), systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .help(selected.isEmpty ? String(localized: "Select photos to share", comment: "Mac toolbar: Share is off with nothing selected")
                                       : String(localized: "Share", comment: "Mac toolbar"))
                .disabled(selected.isEmpty)
                Button { showsInspector.toggle() } label: {
                    Label(showsInspector ? String(localized: "Hide Inspector", comment: "Mac toolbar")
                                         : String(localized: "Show Inspector", comment: "Mac toolbar"),
                          systemImage: "sidebar.right")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(unhideTitle, action: unhide)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .help(String(localized: "\(unhideTitle) (⌘L)", comment: "Mac Hidden: the Unhide button's tooltip with its shortcut"))
                    .disabled(selected.isEmpty || isUnhiding)
            }
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let selectionModel, let photoMenu {
                    MacSelectionInspector(selection: selectionModel, menu: photoMenu, picture: MacRootWindow.demoPicture)
                }
            }
            .inspectorColumnWidth(MacWindowMetrics.inspectorWidth)
        }
        .focusedSceneValue(\.macHidden, MacHiddenTarget(count: selected.count, unhide: unhide))
        .alert(String(localized: "Couldn’t Unhide", comment: "Mac Hidden: unhide failed, title"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Hidden: dismiss"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task {
            if selectionModel == nil { selectionModel = MacSelectionModel(database: dependencies.database) }
            reload()
        }
        // Hidden from another window, or a photo menu here (Move to Trash).
        .onReceive(NotificationCenter.default.publisher(for: .macHiddenChanged)) { _ in reload() }
        .onChange(of: dependencies.photoLibrary.assetChangeToken) { reload() }
        .onDisappear { loadTask?.cancel() }
    }

    private var title: String {
        // Empty, the page says so: the title just names the place.
        guard !items.isEmpty else { return MacSidebarItem.hidden.title }
        return String(AttributedString(localized: "^[\(items.count) Hidden Photo](inflect: true)",
                                comment: "Mac Hidden: window title, '6 Hidden Photos'").characters)
    }

    /// "2 selected · 98.6 MB", or the count and where the copies are.
    private var subtitle: String {
        guard !selected.isEmpty else {
            let count = String(AttributedString(localized: "^[\(items.count) photo](inflect: true)",
                                                comment: "Mac Hidden subtitle: how many").characters)
            return ([count] + sourceNames).joined(separator: " · ")
        }
        let bytes = items.reduce(Int64(0)) { $0 + (selected.contains($1.assetId) ? Int64($1.fileSize ?? 0) : 0) }
        let count = String(localized: "\(selected.count) selected", comment: "Mac toolbar subtitle: photos selected (plural)")
        return bytes > 0 ? count + " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : count
    }

    private var unhideTitle: String {
        selected.isEmpty ? String(localized: "Unhide", comment: "Mac Hidden: the Unhide button with nothing selected")
            : selected.count == 1
            ? String(localized: "Unhide 1 Photo", comment: "Mac Hidden: unhide the selected photo")
            : String(localized: "Unhide \(selected.count) Photos", comment: "Mac Hidden: unhide the selected photos (0 or more than 1)")
    }

    /// What hiding here means (board `MAC_Hidden`): out of the grids until
    /// unhidden, files untouched, and not Photos' own Hidden album.
    private var note: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.slash")
                .accessibilityHidden(true)
                .font(.system(size: 16))
                .foregroundStyle(MacTheme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Photos hidden in ShotDex", comment: "Mac Hidden: the note's title").font(.system(size: 13, weight: .semibold))
                Group {
                    Text(noteText)
                    Text("The Hidden album in Photos is separate and does not appear here; a photo hidden there too stays hidden in Photos after Unhide.",
                         comment: "Mac Hidden: Photos' own Hidden album is not this, and Unhide does not change it")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            // Wraps within the window's width; `fixedSize` here would size the
            // whole split view to the unwrapped text.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var noteText: String {
        // One server holds them all: why they could only be hidden.
        if sourceNames.count == 1, let name = sourceNames.first, sources.first(where: { $0.name == name })?.kind == "server" {
            return String(localized: "They stay out of All Photos, search, albums, smart albums and Statistics until you unhide them. Their files are not changed: these \(items.count) are still on “\(name)”, which ShotDex can only hide, never delete from.",
                          comment: "Mac Hidden: what hiding does, every hidden photo on one server (plural)")
        }
        return String(localized: "They stay out of All Photos, search, albums, smart albums and Statistics until you unhide them. Their files are not changed.",
                      comment: "Mac Hidden: what hiding does")
    }

    /// One read at a time: a newer one cancels the last, so a slow read
    /// cannot land over a fresh one.
    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    /// The hidden photos, where they are and their assets, read off the main
    /// actor; the grid rebuilds only when the rows changed.
    private func load() async {
        let store = HiddenCopyStore(database: dependencies.database)
        let rows: [LibraryGridItem]
        do {
            rows = try await store.hiddenGridItems()
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
            return
        }
        loadError = nil
        let ids = rows.map(\.assetId)
        let (names, found) = await Task.detached(priority: .userInitiated) {
            ((try? store.hiddenSourceNames()) ?? [], MacAssetMap(PhotoLibraryService.fetchAssets(ids: ids)))
        }.value
        guard !Task.isCancelled else { return }
        sourceNames = names
        assets = found
        hasLoaded = true
        guard rows != items else { return }
        items = rows
        generation += 1
        let present = Set(rows.map(\.assetId))
        if !selected.isSubset(of: present) {
            selected.formIntersection(present)
            selectionModel?.set(selected)
        }
    }

    /// Every copy of the selected photos comes back to the grids.
    private func unhide() {
        let ids = Array(selected)
        guard !ids.isEmpty, !isUnhiding else { return }
        isUnhiding = true
        let store = HiddenCopyStore(database: dependencies.database)
        Task {
            defer { isUnhiding = false }
            do {
                try await Task.detached(priority: .userInitiated) { try store.unhide(photoIds: ids) }.value
            } catch {
                failure = error.localizedDescription
                return
            }
            selected = []
            selectionModel?.set([])
            MacPhotoMenu.registerUndo(undoManager, hidden: false, ids: ids, database: dependencies.database)
            NotificationCenter.default.post(name: .macHiddenChanged, object: nil)
        }
    }
}

/// The undo manager's target for Hide and Unhide: the writes are the
/// store's, not any one view's.
@MainActor
final class MacHideUndoTarget {
    static let shared = MacHideUndoTarget()
}

/// PhotoKit assets by id, handed across from a detached fetch. Unchecked
/// because `PHAsset` is not marked Sendable: the map is built off the main
/// actor, handed over once and only read after — and a fetched `PHAsset`
/// does not change.
struct MacAssetMap: @unchecked Sendable {
    let byId: [String: PHAsset]

    init(_ assets: [PHAsset] = []) {
        byId = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Image › Unhide while the Hidden section is in front: ⌘L, the key Hide
/// has everywhere else.
struct MacHiddenTarget {
    var count: Int
    var unhide: () -> Void
}

extension FocusedValues {
    @Entry var macHidden: MacHiddenTarget?
}

extension Notification.Name {
    /// Photos were hidden or unhidden: the grids, the Hidden section and its
    /// sidebar row read again.
    static let macHiddenChanged = Notification.Name("macHiddenChanged")
}

/// A Hide asked for (Image › Hide, the photo menu): the window says what it
/// does and, for photos in Photos and elsewhere, asks which way.
struct MacHideRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let commands: [HideCommand]
    /// A selected photo has a Photos copy: Hide (or Hide in Photos) puts it
    /// in the Photos app's Hidden album too, on every device.
    let touchesPhotos: Bool
}
