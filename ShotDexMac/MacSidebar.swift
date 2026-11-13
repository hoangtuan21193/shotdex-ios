import AppKit
import SwiftUI

/// The sidebar (board `Main`): Library, Sources, Collections, Utilities;
/// counts in secondary on the right, an index status line at the foot.
struct MacSidebar: View {
    @Binding var selection: MacSidebarItem?
    let library: LibraryModel?
    /// Counts on the Library rows and the sources (FS-18.01 §2); Recently
    /// Added has none.
    var counts: [MacSidebarItem: Int] = [:]
    let sources: [SourceStore.Source]
    /// The Backup row's count, or a warning dot when a job needs the user
    /// (FS-22.06 §5.1).
    var backup: (jobs: Int, needsAttention: Bool) = (0, false)
    var smartAlbums: [SmartAlbum] = []
    /// Photos ShotDex hid: the Hidden row shows while there is one (or it is open).
    var hiddenCount = 0
    /// Photos' albums, listed under Albums when it is open (board `MAC_AlbumDetail`).
    var albums: [AlbumSummary] = []
    @AppStorage("macSidebarShowsAlbums") private var showsAlbums = true
    @Environment(MacDependencies.self) private var dependencies
    var newSmartAlbum: () -> Void = {}
    /// The Sources header's + (board `Main`): the Add a Source sheet
    /// (`MAC_AddSource`) — Photos, a folder or drive, or a server.
    var addSource: () -> Void = {}
    /// Folders, drives or cards dropped on the sidebar (FS-18.01 §7).
    var addFolders: ([URL]) -> Void = { _ in }
    /// When the index last finished a pass, for the foot's "indexed 2 min ago".
    var lastIndexedAt: Date? = nil
    /// Sources' states and the read in progress (FS-19.01 §4, 01b §1): read
    /// inside the small views below, so a read's progress does not redraw
    /// the whole sidebar ten times a second.
    var sourcesModel: SourcesModel? = nil
    /// A click on the read's foot line: its banner comes back.
    var showReadBanner: () -> Void = {}
    /// A long task's foot (a common-photos run), shown instead of the index line.
    var busyFooter: AnyView? = nil

    var body: some View {
        list
            // The On Server foot's counts: again on each batch of the check (off main).
            .task(id: dependencies.onServerCheck.generation) {
                await dependencies.onServerStatus.refresh(check: dependencies.onServerCheck, database: dependencies.database)
            }
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach(MacSidebarItem.library) { item in
                    row(item, count: counts[item])
                }
            }
            Section {
                if sources.isEmpty {
                    Text("No sources yet", comment: "Mac sidebar: the Sources group before anything is added")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(sources, id: \.id) { source in
                    Label {
                        MacSourceRowTitle(source: source, count: counts[.source(source.id)], model: sourcesModel)
                    } icon: { MacSidebar.icon(MacSidebar.symbol(forSourceKind: source.kind)) }
                        .tag(MacSidebarItem.source(source.id))
                        .listRowBackground(ground(.source(source.id)))
                }
                // Memory cards ShotDex remembers, while plugged in (FS-20 §4): Import from Card.
                ForEach(dependencies.cards.connected) { card in
                    Label {
                        MacCardRowTitle(card: card)
                    } icon: { MacSidebar.icon("sdcard") }
                        .tag(MacSidebarItem.card(card.id))
                        .listRowBackground(ground(.card(card.id)))
                }
            } header: {
                HStack {
                    Text("Sources", comment: "Mac sidebar group")
                    Spacer()
                    // Add a Source (board `MAC_AddSource`): a sheet, not a menu.
                    Button(action: addSource) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Add Source", comment: "Mac sidebar: add a folder, drive or server"))
                        .accessibilityLabel(String(localized: "Add Source", comment: "Mac sidebar: add a folder, drive or server"))
                        .accessibilityIdentifier("sidebar.addSource")
                }
                // macOS reads a List header as one element: the + is its action.
                .accessibilityAction(named: String(localized: "Add Source", comment: "Mac sidebar: add a folder, drive or server"), addSource)
            }
            Section {
                ForEach(MacSidebarItem.collections) { item in
                    if item == .albums {
                        albumsRow
                        if showsAlbums {
                            // A long list does not bury the rest: the first 12, then Albums for all.
                            ForEach(albums.prefix(MacSidebar.albumRowsShown)) { album in
                                Label {
                                    HStack {
                                        Text(album.title).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if album.count > 0 { MacSidebar.countText(album.count) }
                                    }
                                } icon: { MacSidebar.icon(MacSidebarItem.album(album.id).systemImage) }
                                .padding(.leading, 18)
                                .help(album.title)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(album.title)
                                .accessibilityValue(String(AttributedString(localized: "^[\(album.count) photo](inflect: true)",
                                                                            comment: "Mac sidebar: an album's count, VoiceOver").characters))
                                .tag(MacSidebarItem.album(album.id))
                                .listRowBackground(ground(.album(album.id)))
                            }
                            if albums.count > MacSidebar.albumRowsShown {
                                Label {
                                    Text("Show All Albums…", comment: "Mac sidebar: open Albums for the rest of a long list").foregroundStyle(.secondary)
                                } icon: { MacSidebar.icon("ellipsis") }
                                .padding(.leading, 18)
                                .tag(MacSidebarItem.albums)
                            }
                        }
                    } else {
                        row(item, count: nil)
                    }
                }
                ForEach(smartAlbums) { album in
                    Label { Text(album.name) } icon: { MacSidebar.icon(MacSidebarItem.smartAlbum(album.id).systemImage) }
                        .tag(MacSidebarItem.smartAlbum(album.id))
                        .listRowBackground(ground(.smartAlbum(album.id)))
                }
                if hiddenCount > 0 || selection == .hidden {
                    row(.hidden, count: hiddenCount)
                }
            } header: {
                HStack {
                    Text("Collections", comment: "Mac sidebar group")
                    Spacer()
                    Button(action: newSmartAlbum) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "New Smart Album… (⌥⌘N)", comment: "Mac sidebar: add a smart album"))
                        .accessibilityLabel(String(localized: "New Smart Album", comment: "Mac sidebar: add a smart album"))
                }
                .accessibilityAction(named: String(localized: "New Smart Album", comment: "Mac sidebar: add a smart album"), newSmartAlbum)
            }
            Section(String(localized: "Utilities", comment: "Mac sidebar group")) {
                ForEach(MacSidebarItem.utilities) { item in
                    if item == .backup {
                        backupRow
                    } else {
                        row(item, count: nil)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { status }
        // Anything dropped goes through: a file is refused with a reason.
        .dropDestination(for: URL.self) { urls, _ in
            addFolders(urls)
            return !urls.filter(MacEmptyLibrary.isFolder).isEmpty
        }
        .background(MacSidebarHighlightOff())
    }

    /// The picked row's ground: grey `rowSel` whether or not the sidebar has
    /// the focus (DESIGN.md §10b, D11) — the system draws it in the macOS
    /// accent, blue, once the list is clicked.
    @ViewBuilder
    private func ground(_ item: MacSidebarItem) -> some View {
        if selection == item || (item == .albums && selection?.isOpenedFromAlbums == true && !(showsAlbums && selection?.isListedAlbum(in: albums) == true)) {
            RoundedRectangle(cornerRadius: 8).fill(MacTheme.rowSelection).padding(.horizontal, 8)
        } else {
            Color.clear
        }
    }

    /// Albums with its count and the chevron that shows or hides the list.
    private var albumsRow: some View {
        Label {
            HStack(spacing: 6) {
                Text(MacSidebarItem.albums.title)
                Spacer(minLength: 4)
                // Beside the count, as the board draws it.
                Button { showsAlbums.toggle() } label: {
                    Image(systemName: showsAlbums ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityValue(showsAlbums ? String(localized: "expanded", comment: "Mac sidebar: the album list shows")
                                                : String(localized: "collapsed", comment: "Mac sidebar: the album list is hidden"))
                .foregroundStyle(.secondary)
                .accessibilityLabel(showsAlbums ? String(localized: "Hide Albums", comment: "Mac sidebar: collapse the album list")
                                                : String(localized: "Show Albums", comment: "Mac sidebar: expand the album list"))
                .help(showsAlbums ? String(localized: "Hide Albums", comment: "Mac sidebar: collapse the album list")
                                  : String(localized: "Show Albums", comment: "Mac sidebar: expand the album list"))
                if !albums.isEmpty { MacSidebar.countText(albums.count) }
            }
        } icon: {
            MacSidebar.icon(MacSidebarItem.albums.systemImage)
        }
        .tag(MacSidebarItem.albums)
        .listRowBackground(ground(.albums))
    }

    private func row(_ item: MacSidebarItem, count: Int?) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer(minLength: 4)
                if let count {
                    MacSidebar.countText(count)
                }
            }
        } icon: {
            MacSidebar.icon(item.systemImage)
        }
        .tag(item)
        .listRowBackground(ground(item))
    }

    private var backupRow: some View {
        Label {
            HStack {
                Text(MacSidebarItem.backup.title)
                Spacer(minLength: 4)
                if backup.needsAttention {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .accessibilityLabel(String(localized: "Needs attention", comment: "Mac sidebar: a backup job has a problem"))
                } else if backup.jobs > 0 {
                    MacSidebar.countText(backup.jobs)
                }
            }
        } icon: {
            MacSidebar.icon(MacSidebarItem.backup.systemImage)
        }
        .tag(MacSidebarItem.backup)
        .listRowBackground(ground(.backup))
    }

    @ViewBuilder
    private var status: some View {
        // An upload under way leads the foot (board `MAC_ServerUpload`): the index line returns after.
        let uploading = dependencies.uploads.entries.filter { $0.model.stage == .uploading }
        if !uploading.isEmpty {
            MacUploadFoot(entries: uploading,
                          indexLine: library?.isIndexing == true ? String(localized: "Indexing…", comment: "Mac sidebar foot: the index is running") : nil)
        } else if let busyFooter {
            busyFooter
        } else if let sourcesModel, sourcesModel.hasReadProgress {
            MacReadFoot(model: sourcesModel, showBanner: showReadBanner)
        } else if dependencies.onServerStatus.isShown(dependencies.onServerCheck) {
            // The On Server check matching photos with server files (FS-19.07 §7).
            MacOnServerFoot(status: dependencies.onServerStatus,
                            indexLine: library?.isIndexing == true ? String(localized: "Indexing…", comment: "Mac sidebar foot: the index is running") : nil,
                            // The detail of what runs (user 2026-11-08): Activity › Background.
                            open: {
                                MacWindowRequest.showsActivity = true
                                NotificationCenter.default.post(name: .macShowActivity, object: nil)
                            })
        } else if let library {
            // "Up to date · indexed 2 min ago" (FS-18.01 §2), the age kept
            // current once a minute.
            TimelineView(.everyMinute) { context in
                HStack(spacing: 6) {
                    Image(systemName: library.isIndexing ? "arrow.triangle.2.circlepath" : "checkmark")
                    Text(library.isIndexing
                         ? String(localized: "Indexing…", comment: "Mac sidebar foot: the index is running")
                         : MacSidebar.upToDate(lastIndexedAt: lastIndexedAt, now: context.date))
                    Spacer()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Board `Main`: a 16pt line glyph in the ShotDex accent on every row,
    /// whatever the system accent and whether the window is key — the
    /// default sidebar icon is larger, filled in places and system blue.
    static func icon(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolVariant(.none)
            .fontWeight(.regular)
            .foregroundStyle(MacTheme.accent)
            .frame(width: 16, height: 16)
    }

    /// "Up to date · indexed 2 min ago"; "Up to date" before any pass.
    static func upToDate(lastIndexedAt: Date?, now: Date) -> String {
        guard let lastIndexedAt else { return String(localized: "Up to date", comment: "Mac sidebar foot: the index is finished") }
        // `lastIndexedAt` is the last write to the index (any batch, any run).
        // A date ahead of the clock (the clock set back) says no age at all.
        let age = now.timeIntervalSince(lastIndexedAt)
        guard age >= 0 else { return String(localized: "Up to date", comment: "Mac sidebar foot: the index is finished") }
        // Under a minute reads "just now": a whole sentence, never a fragment spliced in.
        guard age >= 60 else {
            return String(localized: "Up to date · indexed just now", comment: "Mac sidebar foot: indexed less than a minute ago")
        }
        let phrase = lastIndexedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return String(localized: "Up to date · indexed \(phrase)",
                      comment: "Mac sidebar foot: the index finished; the argument is a whole relative phrase such as '2 min. ago'")
    }

    /// Albums listed under the Albums row before "Show All Albums…".
    static let albumRowsShown = 12

    /// A row's count: 11, tabular, secondary (DESIGN.md §10b).
    static func countText(_ count: Int) -> some View {
        Text(count.formatted()).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
    }

    static func symbol(forSourceKind kind: String) -> String {
        switch kind {
        case "photos": "photo.stack"
        case "drive": "externaldrive"
        case "server": "server.rack"
        default: "folder"
        }
    }
}

/// The sidebar's places (board `Main`).
enum MacSidebarItem: Hashable, Identifiable {
    case allPhotos, favorites, videos, raw, recentlyAdded
    case source(String)
    case onThisDay, albums, hidden
    /// Places opened from Albums (FS-18.04 §1): one of Photos' albums, and
    /// People and Pets' two. Not rows of their own.
    case album(String)
    case people, pets
    case smartAlbum(String)
    case backup, statistics, duplicates, collages, videoProjects, onServer
    /// A memory card's Import from Card page (FS-20, board `MAC_Ingest`).
    case card(String)

    var id: String {
        if case .source(let id) = self { return "source-" + id }
        if case .card(let id) = self { return "card-" + id }
        if case .smartAlbum(let id) = self { return "smart-" + id }
        if case .album(let id) = self { return "album-" + id }
        return title
    }

    static let library: [MacSidebarItem] = [.allPhotos, .favorites, .videos, .raw, .recentlyAdded]
    static let collections: [MacSidebarItem] = [.onThisDay, .albums]
    static let utilities: [MacSidebarItem] = [.backup, .statistics, .duplicates, .collages, .videoProjects, .onServer]

    var title: String {
        switch self {
        case .allPhotos: String(localized: "All Photos", comment: "Mac sidebar")
        case .favorites: String(localized: "Favorites", comment: "Mac sidebar")
        case .videos: String(localized: "Videos", comment: "Mac sidebar")
        case .raw: String(localized: "RAW", comment: "Mac sidebar")
        case .recentlyAdded: String(localized: "Recently Added", comment: "Mac sidebar")
        case .source: String(localized: "Source", comment: "Mac sidebar: a photo source")
        case .onThisDay: String(localized: "On This Day", comment: "Mac sidebar")
        case .albums: String(localized: "Albums", comment: "Mac sidebar")
        case .hidden: String(localized: "Hidden", comment: "Mac sidebar: photos hidden in ShotDex")
        case .album: String(localized: "Album", comment: "Mac: one of Photos' albums")
        case .people: String(localized: "People", comment: "Mac Albums: photos with faces")
        case .pets: String(localized: "Pets", comment: "Mac Albums: photos with cats or dogs")
        case .smartAlbum: String(localized: "Smart Album", comment: "Mac sidebar: a smart album")
        case .backup: String(localized: "Backup", comment: "Mac sidebar")
        case .statistics: String(localized: "Statistics", comment: "Mac sidebar")
        case .duplicates: String(localized: "Duplicates", comment: "Mac sidebar")
        case .collages: String(localized: "Collages", comment: "Mac sidebar")
        case .videoProjects: String(localized: "Video Projects", comment: "Mac sidebar")
        case .onServer: String(localized: "On Server", comment: "Mac sidebar")
        case .card: String(localized: "Memory Card", comment: "Mac sidebar: a memory card to import from")
        }
    }

    /// A place whose own screen a later pass of the Mac loop builds
    /// (docs/design/mac/MAC_LOOP.md): it must not show the whole library
    /// under its name meanwhile.
    var isPendingScreen: Bool {
        switch self {
        case .statistics, .collages, .videoProjects: true
        default: false
        }
    }

    /// One of `albums`, so its own row in the list is the lit one.
    func isListedAlbum(in albums: [AlbumSummary]) -> Bool {
        if case .album(let id) = self { albums.contains { $0.id == id } } else { false }
    }

    /// An album, People or Pets: opened from Albums, so Albums stays lit.
    var isOpenedFromAlbums: Bool {
        switch self {
        case .album, .people, .pets: true
        default: false
        }
    }

    var systemImage: String {
        switch self {
        case .allPhotos: "photo.on.rectangle"
        case .favorites: "heart"
        case .videos: "video"
        case .raw: "camera.aperture"
        case .recentlyAdded: "clock"
        case .source: "folder"
        case .onThisDay: "calendar"
        case .albums: "rectangle.stack"
        case .hidden: "eye.slash"
        case .album: "rectangle.stack"
        case .people: "person.2"
        case .pets: "pawprint"
        case .smartAlbum: "sparkles.rectangle.stack"
        case .backup: "clock.arrow.circlepath"
        case .statistics: "chart.bar"
        case .duplicates: "square.on.square"
        case .collages: "square.grid.2x2"
        case .videoProjects: "film"
        case .onServer: "externaldrive.connected.to.line.below"
        case .card: "sdcard"
        }
    }
}

/// Stands in for a place whose screen is not built yet (see
/// `MacSidebarItem.isPendingScreen`).
struct MacPendingPlace: View {
    let item: MacSidebarItem

    var body: some View {
        ContentUnavailableView(item.title, systemImage: item.systemImage,
                               description: Text("Not built on the Mac yet.", comment: "Mac: a sidebar place whose screen is still to come"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(item.title)
    }
}

/// Turns off the sidebar outline view's own selection highlight, so the
/// rows' `rowSel` ground is the only one drawn.
private struct MacSidebarHighlightOff: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    /// Again on every update: the List can rebuild its outline view, and a
    /// fresh one comes back with the blue highlight.
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(from: nsView) }
    }

    /// Applies as soon as it is in a window — before that there is no
    /// outline view next to it.
    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { MacSidebarHighlightOff.apply(from: self) }
        }
    }

    static func apply(from view: NSView) {
        // The outline view is a sibling of this background: search from the
        // nearest ancestor that holds one.
        var ancestor = view.superview
        while let current = ancestor {
            if let outline = find(in: current) {
                outline.selectionHighlightStyle = .none
                return
            }
            ancestor = current.superview
        }
    }

    private static func find(in view: NSView) -> NSOutlineView? {
        if let outline = view as? NSOutlineView { return outline }
        for child in view.subviews { if let found = find(in: child) { return found } }
        return nil
    }
}

/// A source row's name and what is beside it: the read's ring, "Offline",
/// or the count (FS-19.01 §4, 01b §1).
private struct MacSourceRowTitle: View {
    let source: SourceStore.Source
    let count: Int?
    let model: SourcesModel?

    var body: some View {
        let isOffline = model?.rows.first(where: { $0.id == source.id })?.text.status == .offline
        // Only the row being read follows the progress ticks.
        let isReading = model?.readSourceId == source.id || model?.readingSourceId == source.id
        let progress = isReading ? model?.readProgress : nil
        HStack {
            Text(source.name).foregroundStyle(isOffline ? .secondary : .primary)
            Spacer(minLength: 4)
            if isReading {
                MacProgressRing(fraction: progress?.fraction ?? 0)
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "Adding, \(progress?.percent ?? 0) percent",
                                               comment: "Mac sidebar: the source is being read, VoiceOver"))
            } else if isOffline {
                Text("Offline", comment: "Mac sidebar: the drive or server is not connected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(MacTheme.fill))
            } else if let count {
                MacSidebar.countText(count)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOffline ? String(localized: "\(source.name), offline", comment: "Mac sidebar: an offline source, VoiceOver") : source.name)
    }
}

/// "Indexing 1,240 of 3,812 · 33%" over a bar (board `MAC_SourceIndexing`),
/// "Paused · …" once paused; a click brings the banner back.
private struct MacReadFoot: View {
    let model: SourcesModel
    let showBanner: () -> Void

    var body: some View {
        if let progress = model.readProgress {
            Button(action: showBanner) {
                VStack(spacing: 6) {
                    HStack {
                        Text(progress.footLine).foregroundStyle(.primary)
                        Spacer()
                        Text(progress.fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .monospacedDigit()
                    MacProgressBar(fraction: progress.fraction)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(MacTheme.fill))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(8)
            .help(String(localized: "Show Progress", comment: "Mac sidebar foot: bring the source read banner back"))
            .accessibilityIdentifier("sidebar.readFoot")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// A card's sidebar row: its name, and the import's percentage while one
/// runs (FS-20 §7) — read here, so a run's progress redraws only this row.
private struct MacCardRowTitle: View {
    let card: RememberedCard
    @Environment(MacDependencies.self) private var dependencies

    var body: some View {
        HStack(spacing: 6) {
            Text(card.name).lineLimit(1)
            Spacer(minLength: 4)
            if let model = dependencies.cards.center.models[card.id], model.isRunning {
                Text(model.progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if dependencies.cards.canEject(card.id) {
                // As in Finder (board `MAC_Ingest`): the card goes from its row.
                Button {
                    Task {
                        guard await !dependencies.cards.eject(card.id) else { return }
                        NotificationCenter.default.post(name: .macToast, object: String(localized: "\(card.name) couldn't be ejected. Close any app using it and try again.",
                                                                                         comment: "Mac Import from Card: Eject failed"))
                    }
                } label: {
                    Image(systemName: "eject").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(String(localized: "Eject \(card.name)", comment: "Mac Import from Card: Eject's tooltip"))
                .accessibilityLabel(String(localized: "Eject \(card.name)", comment: "Mac Import from Card: Eject's tooltip"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(String(localized: "Memory card", comment: "Mac sidebar: what a card row is, for VoiceOver"))
    }
}
