import Photos
import SwiftUI

/// Collections tab: On This Day hero, then one row of cover tiles per
/// collection group, then the Media Types and Utilities lists.
struct AlbumsScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// One-line card height for the Media Types and Utilities bands, scaled
    /// with the text inside so a row never crops the card.
    @ScaledMetric(relativeTo: .body) private var rowHeight = CollectionListRowMetrics.height
    /// Height of the hero, scaled here rather than inside the card.
    @ScaledMetric(relativeTo: .headline) private var heroScale = 1.0
    private var heroHeight: CGFloat {
        min(
            CollectionsHeroMetrics.height(isRegularWidth: horizontalSizeClass == .regular) * heroScale,
            CollectionsHeroMetrics.maximumHeight(visibleHeight: visibleHeight)
        )
    }
    /// Height of the scroll view, for the hero's cap.
    @State private var visibleHeight: CGFloat = 0

    /// Gap between tiles. Wider where the tiles are, so a row of 168pt covers
    /// does not read as one striped block.
    private var tileSpacing: CGFloat {
        horizontalSizeClass == .regular ? AppTheme.Spacing.md : AppTheme.Spacing.sm
    }
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies

    /// Owned by `RootTabView` so the snapshot is preloaded in the background
    /// after Library first paint. Falls back to a local model for previews.
    private let injectedModel: AlbumsModel?
    /// Network tile being renamed (FS-17.04 §4).
    @State private var renamingShortcut: ServerShortcut?
    @State private var shortcutName = ""
    @State private var fallbackModel = AlbumsModel()
    private var model: AlbumsModel { injectedModel ?? fallbackModel }

    /// The library index is still running — handed on to Statistics, whose
    /// Insights card says it describes only what has been read so far.
    private let isLibraryIndexing: Bool

    init(model: AlbumsModel? = nil, isLibraryIndexing: Bool = false) {
        self.isLibraryIndexing = isLibraryIndexing
        self.injectedModel = model
    }

    @State private var isCreatingSmartAlbum = false
    @State private var isCustomizePresented = false
    @State private var editingSmartAlbum: SmartAlbum?
    /// A smart album kept in Photos, waiting for the delete to be confirmed
    /// (FS-06.12 AC-9). Others delete at once, as before.
    @State private var deletingKeptSmartAlbum: SmartAlbum?
    @State private var namingRequest: NamingRequest?
    @State private var enteredName = ""
    @State private var deletionRequest: DeletionRequest?

    /// A pending "type a name" alert — creating an album or renaming one.
    /// One piece of state for both, because they differ only in the title and
    /// what happens on confirm.
    struct NamingRequest: Identifiable {
        enum Kind {
            case newAlbum
            case renameAlbum(AlbumItem)
        }

        let id = UUID()
        let kind: Kind

        var title: String {
            switch kind {
            case .newAlbum: String(localized: "New Album")
            case .renameAlbum: String(localized: "Rename Album")
            }
        }

        var confirmTitle: String {
            switch kind {
            case .newAlbum: String(localized: "Create")
            case .renameAlbum: String(localized: "Rename")
            }
        }

        var currentName: String {
            switch kind {
            case .newAlbum: ""
            case .renameAlbum(let album): album.title
            }
        }
    }

    /// A pending delete, confirmed before it happens. Deleting an album never
    /// deletes photos — the message says so, because that is the one thing a
    /// user needs to be sure of here.
    struct DeletionRequest: Identifiable {
        enum Target {
            case album(AlbumItem)
        }

        let id = UUID()
        let target: Target

        var title: String {
            switch target {
            case .album(let album): String(localized: "Delete “\(album.title)”?")
            }
        }

        var message: String {
            switch target {
            case .album:
                String(localized: "The photos stay in your library.")
            }
        }
    }

    var body: some View {
        Group {
            if photoLibrary.authorizationState.canReadLibrary
                || dependencies.sources.rows.contains(where: { $0.text.kind != .photos }) {
                albumGrid
            } else {
                ContentUnavailableView {
                    Label("No Access to Photos", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("Allow photo access in the Library tab to browse albums.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsButton()
            }
            // Separate item so the "+" gets its own Liquid Glass circle on
            // iOS 26 instead of sharing the settings button's capsule.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        namingRequest = NamingRequest(kind: .newAlbum)
                    } label: {
                        Label("New Album", systemImage: "plus.rectangle.on.rectangle")
                    }
                    Button {
                        isCreatingSmartAlbum = true
                    } label: {
                        Label("New Smart Album", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Divider()
                    Button {
                        isCustomizePresented = true
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .tint(.primary)
                .accessibilityLabel("New album or smart album, or customize this tab")
            }
        }
        // The asset token and the collection token, not `libraryChangeToken`.
        // `libraryChangeToken` also fires on content-only notifications —
        // PhotoKit caching a rendition, a favorite toggled — about once a
        // second while iCloud streams during an index run, and rebuilding
        // this whole snapshot that often is what made the tab flicker. The
        // two narrow tokens cover what this tab actually draws: the asset one
        // for covers and membership, the collection one for an album being
        // created, renamed or deleted, which moves no asset and so used to
        // leave a just-made album invisible until the next launch.
        .task(id: photoLibrary.collectionsTabTokens) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            if model.dependencies == nil { model.dependencies = dependencies }
            model.load(forChangeTokens: photoLibrary.collectionsTabTokens)
        }
        .collectionsDestinations(model: model, isLibraryIndexing: isLibraryIndexing)
        .task {
            dependencies.fileServerCatalog.reload()
            dependencies.serverShortcuts.reload()
            dependencies.sources.load()
        }
        .alert("Rename", isPresented: Binding(get: { renamingShortcut != nil }, set: { if !$0 { renamingShortcut = nil } }), presenting: renamingShortcut) { shortcut in
            TextField("Name", text: $shortcutName)
            Button("Rename") { dependencies.serverShortcuts.rename(shortcut.id, to: shortcutName) }
                .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only the name in Collections changes. The folder on the server keeps its name.", comment: "Rename a Network tile")
        }
        .sheet(isPresented: $isCustomizePresented) {
            CustomizeCollectionsSheet(store: dependencies.collectionsLayout)
        }
        .formSheet(isPresented: $isCreatingSmartAlbum) {
            SmartAlbumEditorSheet(existing: nil, dependencies: dependencies) {
                model.load()
            }
        }
        .alert(
            namingRequest?.title ?? "",
            isPresented: Binding(
                get: { namingRequest != nil },
                set: { if !$0 { namingRequest = nil } }
            ),
            presenting: namingRequest
        ) { request in
            TextField("Name", text: $enteredName)
            Button("Cancel", role: .cancel) { namingRequest = nil }
            Button(request.confirmTitle) { apply(request) }
        }
        .onChange(of: namingRequest?.id) { _, _ in
            enteredName = namingRequest?.currentName ?? ""
        }
        .alert(
            deletionRequest?.title ?? "",
            isPresented: Binding(
                get: { deletionRequest != nil },
                set: { if !$0 { deletionRequest = nil } }
            ),
            presenting: deletionRequest
        ) { request in
            Button("Cancel", role: .cancel) { deletionRequest = nil }
            Button("Delete", role: .destructive) { confirmDelete(request) }
        } message: { request in
            Text(request.message)
        }
        .alert(
            deletingKeptSmartAlbum.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deletingKeptSmartAlbum != nil },
                set: { if !$0 { deletingKeptSmartAlbum = nil } }
            ),
            presenting: deletingKeptSmartAlbum
        ) { album in
            Button("Cancel", role: .cancel) { deletingKeptSmartAlbum = nil }
            Button("Delete", role: .destructive) { model.deleteSmartAlbum(id: album.id) }
        } message: { album in
            Text("This deletes the smart album. The album “\(album.name)” stays in Photos.")
        }
        .formSheet(item: $editingSmartAlbum) { album in
            SmartAlbumEditorSheet(existing: album, dependencies: dependencies) {
                model.load()
            }
        }
    }

    /// One section of the tab, drawn only when it has something in it.
    ///
    /// An empty section is worse than a missing one: it takes a screenful of
    /// scrolling to pass and says nothing. The exception is Utilities, which is
    /// the tools and is always there.
    @ViewBuilder
    private func sectionView(_ section: CollectionsSection) -> some View {
        switch section {
        case .pinned:
            if !pinnedAlbums.isEmpty || !pinnedSmartAlbums.isEmpty
                || !pinnedUtilities.isEmpty {
                pinnedSection()
            }
        case .subjects:
            if !subjectTokens.isEmpty { subjectsSection() }
        case .smartAlbums:
            if !(model.smartQueryAlbums.isEmpty && model.smartAlbums.isEmpty) {
                smartAlbumsSection()
            }
        case .mediaTypes:
            if !model.mediaTypeAlbums.isEmpty { mediaTypesSection() }
        case .myAlbums:
            if !model.userAlbums.isEmpty {
                albumTokenSection(title: "My Albums", albums: model.userAlbums)
            }
        case .sharedAlbums:
            if !model.sharedAlbums.isEmpty {
                albumTokenSection(title: "Shared Albums", albums: model.sharedAlbums)
            }
        case .network:
            if !dependencies.serverShortcuts.shortcuts.isEmpty { networkSection() }
        }
    }

    /// Network (FS-17.04): folders on a server kept as tiles. They look like
    /// albums so they sit in the same row, with a server glyph so they are
    /// not mistaken for one; opening one is the server browser, whose menu
    /// is the Files one — never album Edit or Compress on server files.
    private func networkSection() -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Network")
                .font(.title2.bold())
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(dependencies.serverShortcuts.shortcuts) { shortcut in
                        NavigationLink(value: ServerShortcutRoute(id: shortcut.id)) {
                            NetworkShortcutTile(
                                shortcut: shortcut,
                                connectionName: dependencies.fileServerCatalog.servers.first { $0.id == shortcut.serverId }?.name ?? ""
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                renamingShortcut = shortcut
                                shortcutName = shortcut.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                dependencies.serverShortcuts.remove(shortcut.id)
                            } label: {
                                Label("Remove from Collections", systemImage: "folder.badge.minus")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    /// The top row: On This Day, full width, and nothing beside it.
    private var heroRow: some View {
        NavigationLink(value: OnThisDayDestination()) {
            OnThisDayCard(
                count: model.onThisDayCount,
                coverAsset: model.onThisDayCover
            )
        }
        .buttonStyle(.plain)
        .frame(height: heroHeight)
        .padding(.horizontal)
    }

    private var albumGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                if photoLibrary.authorizationState == .limited {
                    LimitedAccessBanner {
                        photoLibrary.presentLimitedLibraryPicker()
                    }
                    .padding(.top, 4)
                }

                heroRow

                ForEach(dependencies.collectionsLayout.visibleOrder) { section in
                    sectionView(section)
                }

                // Last, under Utilities: where the photos live is set up
                // once and checked now and then, not browsed every visit.
                // Only once there is more than the Photos library: a
                // Photos-only library reads as it always has.
                if dependencies.sources.rows.count > 1 {
                    SourcesGroup()
                }

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
            // The last section is Sources (or Utilities), and the scroll view's bottom
            // inset stops exactly at the floating tab bar — so its tokens sat
            // right against it. Two section gaps of air below the last row;
            // one was still read as touching.
            .padding(.bottom, AppTheme.Spacing.xxl * 2)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
    }

    /// Every pinned album still present in the library, in pin order. Pins
    /// that no longer resolve are dropped rather than shown as errors — an
    /// album can be deleted from Photos while a pin still names it.
    private var pinnedAlbums: [AlbumItem] {
        let all = model.albums
        return dependencies.collectionPins.pinned.compactMap { target in
            guard case .album(let id) = target else { return nil }
            return all.first { $0.id == id }
        }
    }

    private var pinnedSmartAlbums: [SmartAlbumTokenItem] {
        dependencies.collectionPins.pinned.compactMap { target in
            guard case .smartAlbum(let id) = target else { return nil }
            return model.smartQueryAlbums.first { $0.album.id == id }
        }
    }

    private var pinnedUtilities: [CollectionPinStore.Target] {
        dependencies.collectionPins.pinned.filter { target in
            switch target {
            case .duplicates: true
            default: false
            }
        }
    }

    /// The recent-activity collections that actually have something in them.
    /// An empty "Recently Viewed" is worse than none: it invites a tap that
    /// leads nowhere.

    /// People and Pets, shown only once the opt-in scan has found some. An
    /// empty People row would read as "you have no photos of anyone" when it
    /// really means "nothing has looked yet", so the invitation to scan lives
    /// in Settings instead.
    private var subjectTokens: [(title: String, subtitle: String, symbol: String, ids: [String])] {
        var result: [(String, String, String, [String])] = []
        let people = model.peopleAssetIds
        if !people.isEmpty {
            result.append((
                String(localized: "People"),
                Self.photoCountLabel(people.count),
                "person.crop.square",
                people
            ))
        }
        let pets = model.petAssetIds
        if !pets.isEmpty {
            result.append((
                String(localized: "Pets"),
                Self.photoCountLabel(pets.count),
                "pawprint",
                pets
            ))
        }
        return result
    }

    private static func photoCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 photo")
            : String(localized: "\(count) photos")
    }

    @ViewBuilder
    private func pinButton(_ target: CollectionPinStore.Target) -> some View {
        let isPinned = dependencies.collectionPins.isPinned(target)
        Button {
            dependencies.collectionPins.toggle(target)
        } label: {
            Label(
                isPinned ? "Unpin" : "Pin to Top",
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }
    }

    private func apply(_ request: NamingRequest) {
        let name = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        namingRequest = nil
        guard !name.isEmpty else { return }
        switch request.kind {
        case .newAlbum: model.createAlbum(named: name)
        case .renameAlbum(let album): model.rename(album, to: name)
        }
    }

    private func confirmDelete(_ request: DeletionRequest) {
        deletionRequest = nil
        switch request.target {
        case .album(let album): model.delete(album)
        }
    }

    /// Optional header + horizontal-scrolling grid of uniform album tokens
    /// (cover thumbnail + name + count). Fills up to 3 rows column-major
    /// before scrolling right, like the iOS Photos pinned-collections grid.
    /// Used for smart albums (no header), "My Albums", and "Shared Albums".
    private func albumTokenSection(title: String?, albums: [AlbumItem]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let title {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(albums) { album in
                        NavigationLink(value: album.id) {
                            AlbumToken(album: album)
                        }
                        .buttonStyle(.plain)
                        .albumDropTarget(
                            collection: album.assetCollection,
                            photoLibrary: photoLibrary,
                            onAdded: { model.load() }
                        )
                        .contextMenu {
                            // System albums (Recents, Videos, …) reject both,
                            // so the menu is only offered on the user's own.
                            pinButton(.album(album.id))
                            if album.group == .user {
                                Button {
                                    namingRequest = NamingRequest(kind: .renameAlbum(album))
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deletionRequest = DeletionRequest(target: .album(album))
                                } label: {
                                    Label("Delete Album", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    /// "Smart Albums" section: user-created smart albums (saved filters) first,
    /// then the Apple system smart albums, in one token grid under a shared
    /// header. User tokens push a `SmartAlbumDetailScreen` (staying in this tab)
    /// and offer Edit / Delete via context menu; system tokens push the normal
    /// `AlbumDetailScreen`.
    private func smartAlbumsSection() -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Smart Albums")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(model.smartQueryAlbums) { item in
                        NavigationLink(value: SmartAlbumDestination(id: item.album.id)) {
                            SmartAlbumToken(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            pinButton(.smartAlbum(item.album.id))
                            Button {
                                editingSmartAlbum = item.album
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                let album = item.album
                                let links = SmartAlbumPhotosAlbumStore(database: dependencies.database)
                                Task {
                                    let link = await Task.detached { try? links.link(album.id) }.value
                                    // Any album ShotDex made in Photos, kept or not: say it stays.
                                    if link?.collectionLocalId != nil {
                                        deletingKeptSmartAlbum = album
                                    } else {
                                        model.deleteSmartAlbum(id: album.id)
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    ForEach(model.smartAlbums) { album in
                        NavigationLink(value: album.id) {
                            AlbumToken(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

/// The two list sections: Media Types and Utilities.
///
/// Both are **cards one line of text tall**, packed up to three rows deep and
/// scrolled sideways — the same shape the album sections use, minus the cover
/// well. Media Types sits directly above Utilities.
///
/// One line rather than the old two-line 60pt token because these entries
/// have nothing to show but their name and their count, and no cover worth
/// recognising: "Panoramas" is a word, not a picture. Three rows rather than
/// one because a word-sized card is small, and stacking them is how Photos
/// fills a heading's band without making the band tall.
extension AlbumsScreen {
    /// Capture formats — Videos, Selfies, Live Photos, Portrait, RAW and the
    /// rest. Above Utilities because these are still *photos*; Utilities is
    /// the tools.
    fileprivate func mediaTypesSection() -> some View {
        listSection("Media Types", entryCount: model.mediaTypeAlbums.count) {
            ForEach(model.mediaTypeAlbums) { album in
                NavigationLink(value: album.id) {
                    CollectionListRow(
                        title: album.title,
                        systemImage: album.symbolName ?? "photo.on.rectangle",
                        spokenDetail: String(
                            localized: "\(album.count) photos",
                            comment: "VoiceOver detail on a Media Types row: how many photos it holds"
                        )
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { pinButton(.album(album.id)) }
            }
        }
    }

    /// Title, then the rows. One shape for both sections so they cannot drift
    /// apart.
    ///
    /// Up to three rows of cards, then sideways — the same band the album
    /// sections use. Not a full-width stack: a card the full width of a 13"
    /// iPad puts the count 800pt from the name it belongs to, and a list that
    /// long pushes everything under it off the screen.
    private func listSection(
        _ title: LocalizedStringKey,
        entryCount: Int,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        let rowCount = listRowCount(entryCount)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(
                        repeating: GridItem(.fixed(rowHeight), spacing: AppTheme.Spacing.sm),
                        count: rowCount
                    ),
                    spacing: AppTheme.Spacing.sm
                ) {
                    rows()
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    /// How many rows the band stacks before it starts scrolling sideways.
    ///
    /// Driven by how many cards are actually *visible* — about two at 190pt
    /// on a phone, about four at 240pt on a 13" iPad — so the band fills the
    /// rows it has before hiding anything. Measured the other way round
    /// first: five utilities packed three-per-row put Videos off the right
    /// edge with no peek to say it was there, on the very build that added
    /// it. Capped at three, because a fourth row of word-sized cards is
    /// taller than the section it belongs to.
    private func listRowCount(_ count: Int) -> Int {
        let visibleColumns = horizontalSizeClass == .regular ? 4 : 2
        return max(1, min(3, (count + visibleColumns - 1) / visibleColumns))
    }

}

/// One full-width row in Media Types or Utilities: a small leading glyph, the
/// name, what there is of it, and a chevron.
///
/// Deliberately not `AlbumToken`'s 44pt cover well — at one row per line the
/// glyph is an identifier, not a picture, and a 44pt tinted square beside a
/// single line of text reads as a thumbnail that failed to load.
struct CollectionListRow: View {
    let title: String
    let systemImage: String
    /// Said out loud but never drawn. Counts left this tab: a number beside
    /// every name is noise on a screen whose job is "which one is this", and
    /// the destination states it anyway. VoiceOver keeps it, because there
    /// the count costs nothing and answers "is this worth opening".
    var spokenDetail: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Scaled against `.subheadline`, the card's own title style — not
    // `.body`. `.body` keeps growing into the accessibility sizes after
    // `.subheadline` and `.caption` have capped, so a `.body` box around
    // `.subheadline` text ends up mostly empty at AX sizes.
    @ScaledMetric(relativeTo: .subheadline) private var glyphWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight = CollectionListRowMetrics.height
    @ScaledMetric(relativeTo: .subheadline) private var typeScale = 1.0

    private var width: CGFloat {
        CollectionListRowMetrics.width(isRegularWidth: horizontalSizeClass == .regular) * typeScale
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.body)
                // Not accent: `DESIGN.md` §10.6 keeps accent for active and
                // selected state, and a row's identifying glyph is neither.
                .foregroundStyle(.secondary)
                .frame(width: glyphWidth)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                // A width chosen from the longest *English* name cannot hold
                // every translation of it — German's "Bildschirmaufnahmen"
                // is half again as long. Shrink before truncating: a name
                // one point smaller still reads, half a name does not.
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(width: width, height: rowHeight, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDetail.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
    }
}

enum CollectionListRowMetrics {
    /// One line of text with room to breathe, and past the 44pt minimum
    /// target on its own.
    static let height: CGFloat = 52
    /// Card width, set from the longest name the band can actually carry.
    ///
    /// The card spends 64pt on chrome — 12pt of padding each side, a 24pt
    /// glyph, and the `HStack`'s 8pt on both sides of the name — so the name
    /// gets `width - 64`. Measured at `.subheadline` semibold, the longest
    /// names this tab draws are "Screen Recordings" at **135pt** and
    /// "Unable to Upload" at 123; at 190 the name had 126 and the first of
    /// those lost its last letters. 215 gives it 151 — the measured worst
    /// case plus room for a longer translation of a shorter word.
    ///
    /// Wider again on a regular-width window for the same reason the cover
    /// tiles are bigger there: the band is horizontal, so width is what a
    /// wide screen has to give.
    static let compactWidth: CGFloat = 215
    static let regularWidth: CGFloat = 270

    static func width(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? regularWidth : compactWidth
    }
}

extension AlbumsScreen {

    fileprivate func subjectsSection() -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("People and Pets")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(subjectTokens, id: \.title) { token in
                        NavigationLink {
                            PhotoListScreen(
                                title: token.title,
                                subtitle: token.subtitle,
                                assetIds: token.ids
                            )
                        } label: {
                            UtilityToken(
                                title: token.title,
                                subtitle: token.subtitle,
                                systemImage: token.symbol
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    /// Whatever the user pinned, in the order they pinned it, above everything
    /// the app decided to show.
    fileprivate func pinnedSection() -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Pinned")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(pinnedAlbums) { album in
                        NavigationLink(value: album.id) {
                            AlbumToken(album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { pinButton(.album(album.id)) }
                    }
                    ForEach(pinnedSmartAlbums) { item in
                        NavigationLink(value: SmartAlbumDestination(id: item.album.id)) {
                            SmartAlbumToken(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { pinButton(.smartAlbum(item.album.id)) }
                    }
                    ForEach(pinnedUtilities, id: \.self) { target in
                        pinnedUtilityLink(target)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    fileprivate func pinnedUtilityLink(_ target: CollectionPinStore.Target) -> some View {
        switch target {
        case .duplicates:
            NavigationLink(value: DuplicatesDestination()) {
                DuplicatesToken()
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.duplicates) }
        default:
            EmptyView()
        }
    }

}

/// Navigation value for a user-created smart album's detail screen. Distinct
/// type from `AlbumItem.ID` (also `String`) so it routes to
/// `SmartAlbumDetailScreen` rather than the existing `AlbumItem.ID` destination.
struct SmartAlbumDestination: Hashable {
    let id: String
}

/// One album as a cover tile: the album's first photo, its name and its count.
struct AlbumToken: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let album: AlbumItem

    @State private var cover: UIImage?
    @State private var needsScrim = false
    /// Assets warmed for this album's detail grid, so caching is cancelled
    /// again when the token scrolls away.
    @State private var prewarmedAssets: [PHAsset] = []
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var coverSide: CGFloat {
        AlbumTileMetrics.side(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        AlbumCoverTile(
            title: album.title,
            accessibilityLabel: String(
                localized: "\(album.title), \(album.count) photos",
                comment: "VoiceOver label for an album tile: its name and how many photos it holds"
            ),
            needsScrim: needsScrim
        ) {
            AlbumCoverWell(image: cover, systemImage: album.symbolName ?? "photo.on.rectangle")
        }
        .onAppear {
            loadCover()
            prewarmDetailGrid()
        }
        .onDisappear(perform: stopPrewarmingDetailGrid)
    }

    /// Warms the first screenful of this album's detail grid while its token is
    /// on screen. Opening an album costs 16ms of data and then 120 thumbnail
    /// renditions from cold — the renditions are the wait, and they can be paid
    /// for before the tap.
    private func prewarmDetailGrid() {
        guard prewarmedAssets.isEmpty else { return }
        let targetSize = GridThumbnailTarget.fullWidthThumbnailSize(columns: storedColumns)
        let count = GridThumbnailTarget.prewarmCount(columns: storedColumns)
        let album = album
        Task {
            let assets = await Task.detached(priority: .utility) {
                AlbumsModel.firstAssets(of: album, limit: count)
            }.value
            guard !Task.isCancelled, !assets.isEmpty else { return }
            prewarmedAssets = assets
            photoLibrary.startCachingThumbnails(for: assets, targetSize: targetSize)
        }
    }

    private func stopPrewarmingDetailGrid() {
        guard !prewarmedAssets.isEmpty else { return }
        photoLibrary.stopCachingThumbnails(
            for: prewarmedAssets,
            targetSize: GridThumbnailTarget.fullWidthThumbnailSize(columns: storedColumns)
        )
        prewarmedAssets = []
    }

    private func loadCover() {
        guard cover == nil, let asset = album.coverAsset else { return }
        // A 168pt tile at 3x wants 504px; the old 44pt thumbnail request
        // scaled up to this size is the blur a bigger cover would otherwise
        // buy us.
        let side = coverSide * ActiveDisplay.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            allowNetwork: false
        ) { image in
            if let image {
                cover = image
                needsScrim = CoverTitleScrim.isNeeded(for: image)
            }
        }
    }
}

/// One user-created smart album as a cover tile: the first photo that matches
/// it, its name and its live match count.
struct SmartAlbumToken: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let item: SmartAlbumTokenItem

    @State private var cover: UIImage?
    @State private var needsScrim = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var coverSide: CGFloat {
        AlbumTileMetrics.side(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        AlbumCoverTile(
            title: item.album.name,
            accessibilityLabel: String(
                localized: "\(item.album.name), \(item.count) photos",
                comment: "VoiceOver label for a smart album tile: its name and how many photos match it"
            ),
            needsScrim: needsScrim
        ) {
            AlbumCoverWell(image: cover, systemImage: "line.3.horizontal.decrease.circle")
        }
        .onAppear(perform: loadCover)
    }

    private func loadCover() {
        guard cover == nil, let asset = item.coverAsset else { return }
        let side = coverSide * ActiveDisplay.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            allowNetwork: false
        ) { image in
            if let image {
                cover = image
                needsScrim = CoverTitleScrim.isNeeded(for: image)
            }
        }
    }
}

/// A tile for something that has no cover photo of its own — Duplicates,
/// Recently Viewed. Same tile, a glyph in the cover well.
struct UtilityToken: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        // The subtitle is no longer drawn, so it survives only where it
        // still helps: out loud.
        AlbumCoverTile(
            title: title,
            accessibilityLabel: "\(title), \(subtitle)"
        ) {
            AlbumCoverWell(image: nil, systemImage: systemImage)
        }
    }
}

/// The Duplicates tile, whose second line is what the last scan could free
/// (FS-06.06 §7.1) — or the group count when nothing is to free.
struct DuplicatesToken: View {
    @AppStorage(SettingsKeys.duplicateGroupCount) private var groupCount: Int?
    @AppStorage(SettingsKeys.duplicateFreeBytes) private var freeBytes: Int?

    var body: some View {
        UtilityToken(title: String(localized: "Duplicates"), subtitle: subtitle, systemImage: "square.on.square")
    }

    private var subtitle: String {
        guard let groupCount else {
            return String(
                localized: "Scan library",
                comment: "Duplicates tile subtitle before the first scan"
            )
        }
        if let freeBytes, freeBytes > 0 {
            let size = ByteCountFormatter.string(fromByteCount: Int64(freeBytes), countStyle: .file)
            return String(localized: "~\(size) to free",
                          comment: "Detail on the Duplicates row in Collections: space keeping one per group would free")
        }
        return String(
            localized: "\(groupCount) groups",
            comment: "Detail on the Duplicates row in Collections: how many duplicate groups the last scan found"
        )
    }
}

/// Full-width hero card for the "On This Day" smart album: cover photo
/// with a gradient scrim, today's date, and the match count.
struct OnThisDayCard: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let count: Int
    let coverAsset: PHAsset?

    @State private var cover: UIImage?

    var body: some View {
        // Height comes from the row, which sets it once for the hero and the
        // recents column beside it so the two stay level.
        Color(.secondarySystemBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(cover == nil ? 0.25 : 0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On This Day")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .foregroundStyle(cover == nil ? Color(.label) : .white)
                .padding(AppTheme.Spacing.lg)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(cover == nil ? Color(.secondaryLabel) : .white)
                    .padding(AppTheme.Spacing.lg)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            // `coverAsset` is filled asynchronously by AlbumsModel, so
            // onAppear alone can miss it when this card appears first.
            .task(id: coverAsset?.localIdentifier) {
                loadCover()
            }
            .accessibilityElement(children: .ignore)
            // The same sentence a sighted user reads, rather than a second
            // one written by hand that leaves the date out.
            .accessibilityLabel("On This Day, \(subtitle)")
    }

    /// "September 20 · 3 photos from previous years".
    ///
    /// Localized and inflected: this was a plain interpolation, so it read
    /// "1 photos" on any day with a single match and stayed English in every
    /// language.
    private var subtitle: String {
        let date = Date.now.formatted(.dateTime.month(.wide).day())
        guard count > 0 else {
            return String(
                localized: "\(date) · No photos in previous years",
                comment: "On This Day card subtitle when nothing matches today's date"
            )
        }
        return String(
            localized: "\(date) · \(count) photo from previous years",
            comment: "On This Day card subtitle: the date and how many photos it found"
        )
    }

    private func loadCover() {
        cover = nil
        guard let asset = coverAsset else { return }
        let requestedAssetID = asset.localIdentifier
        _ = photoLibrary.requestAlbumCover(
            for: asset,
            targetSize: AlbumsModel.onThisDayCoverTargetSize,
            allowNetwork: true
        ) { image in
            if requestedAssetID == coverAsset?.localIdentifier, let image {
                cover = image
            }
        }
    }
}

/// Geometry for the Collections tab's top row.
enum CollectionsHeroMetrics {
    /// The hero's height. Taller on a wide window for the same reason the
    /// cover tiles are bigger there: the card is full width, so at 1032pt a
    /// 150pt hero is a letterbox strip rather than a picture. Scaled with
    /// Dynamic Type by the screen, not by the card.
    static func height(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 260 : 180
    }

    /// The most of the visible height the hero may take, Dynamic Type
    /// included. Regular width is not the same as tall: the Duo's inner
    /// display is regular but 669pt, where 260 was 42% of the first screen.
    /// Above 930pt (iPad, a tall iPhone) the cap never binds.
    static let maximumShareOfHeight: CGFloat = 0.28

    static func maximumHeight(visibleHeight: CGFloat) -> CGFloat {
        visibleHeight > 0 ? (visibleHeight * maximumShareOfHeight).rounded() : .infinity
    }
}


