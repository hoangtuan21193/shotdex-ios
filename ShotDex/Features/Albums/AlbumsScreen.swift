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
        CollectionsHeroMetrics.height(isRegularWidth: horizontalSizeClass == .regular) * heroScale
    }

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
    @State private var fallbackModel = AlbumsModel()
    private var model: AlbumsModel { injectedModel ?? fallbackModel }

    init(model: AlbumsModel? = nil) {
        self.injectedModel = model
    }

    @State private var isCreatingSmartAlbum = false
    @State private var isCustomizePresented = false
    @State private var editingSmartAlbum: SmartAlbum?
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
            if photoLibrary.authorizationState.canReadLibrary {
                albumGrid
            } else {
                ContentUnavailableView(
                    "No Access to Photos",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Allow photo access in the Library tab to browse albums.")
                )
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
        .navigationDestination(for: AlbumItem.ID.self) { albumId in
            if let album = model.albums.first(where: { $0.id == albumId }) {
                AlbumDetailScreen(album: album)
            }
        }
        .navigationDestination(for: OnThisDayDestination.self) { destination in
            OnThisDayScreen(initialDate: destination.date ?? .now)
        }
        .navigationDestination(for: SmartAlbumDestination.self) { destination in
            if let item = model.smartQueryAlbums.first(where: { $0.album.id == destination.id }) {
                SmartAlbumDetailScreen(album: item.album)
            }
        }
        .navigationDestination(for: DuplicatesDestination.self) { _ in
            DuplicatesScreen()
        }
        .navigationDestination(for: PlacesDestination.self) { _ in
            PlacesMapScreen()
        }
        .navigationDestination(for: TripsDestination.self) { _ in
            TripsScreen()
        }
        .navigationDestination(for: CreationsDestination.self) { destination in
            CreationsScreen(kind: destination.kind)
        }
        .sheet(isPresented: $isCustomizePresented) {
            CustomizeCollectionsSheet(store: dependencies.collectionsLayout)
        }
        .sheet(isPresented: $isCreatingSmartAlbum) {
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
        .sheet(item: $editingSmartAlbum) { album in
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
        case .memories:
            if !model.memories.isEmpty { memoriesSection() }
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
        case .utilities:
            utilitiesSection()
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

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
            // The last section is Utilities, and the scroll view's bottom
            // inset stops exactly at the floating tab bar — so its tokens sat
            // right against it. Two section gaps of air below the last row;
            // one was still read as touching.
            .padding(.bottom, AppTheme.Spacing.xxl * 2)
        }
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
            case .places, .trips, .duplicates: true
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
                                model.deleteSmartAlbum(id: item.album.id)
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

    fileprivate func utilitiesSection() -> some View {
        listSection("Utilities", entryCount: utilityEntryCount) {
            NavigationLink(value: DuplicatesDestination()) {
                CollectionListRow(
                    title: String(localized: "Duplicates"),
                    systemImage: "square.on.square",
                    spokenDetail: duplicatesCount.map {
                        String(
                            localized: "\($0) groups",
                            comment: "VoiceOver detail on the Duplicates row: how many duplicate groups the last scan found"
                        )
                    }
                )
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.duplicates) }

            NavigationLink(value: PlacesDestination()) {
                CollectionListRow(title: String(localized: "Places"), systemImage: "map")
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.places) }

            NavigationLink(value: TripsDestination()) {
                CollectionListRow(title: String(localized: "Trips"), systemImage: "airplane")
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.trips) }

            // What this app has made, split by the editor that made it:
            // "Creations" as one row said nothing about what was inside, and
            // a collage and a video are started from different places and
            // edited by different tools. Both rows are always here, empty or
            // not — each one is also where you start a new one.
            NavigationLink(value: CreationsDestination(kind: .collage)) {
                CollectionListRow(title: String(localized: "Collages"), systemImage: "square.grid.2x2")
            }
            .buttonStyle(.plain)

            // "Video Projects", because Media Types already has a Videos
            // album and that one means the footage the user shot. These are
            // the things the Video Studio made and can reopen.
            NavigationLink(value: CreationsDestination(kind: .video)) {
                CollectionListRow(
                    title: String(localized: "Video Projects", comment: "Utilities row: videos made in the Video Studio"),
                    systemImage: "film"
                )
            }
            .buttonStyle(.plain)

            // Recently Deleted and Unable to Upload: library housekeeping
            // rather than browsing, so they sit with Duplicates the way
            // Photos groups its own utilities.
            ForEach(model.utilityAlbums) { album in
                NavigationLink(value: album.id) {
                    CollectionListRow(
                        title: album.title,
                        systemImage: album.symbolName ?? "wrench.and.screwdriver",
                        spokenDetail: String(
                            localized: "\(album.count) photos",
                            comment: "VoiceOver detail on a Utilities album row: how many photos it holds"
                        )
                    )
                }
                .buttonStyle(.plain)
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

    /// Duplicates, Places, Trips, Collages and Videos are always drawn; the
    /// system utility albums come and go, and the packing has to count what
    /// is actually there.
    private var utilityEntryCount: Int {
        5 + model.utilityAlbums.count
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

    /// How many duplicate groups the last scan found, as a bare number.
    ///
    /// The word used to be here — "2 groups" — and it does not fit: a 190pt
    /// card holds "Duplicates" and a short detail, and measured on an iPhone
    /// the name came out as "Duplica… 2 groups". Every other card in these
    /// two bands shows a bare count beside the name, so this one does too,
    /// and the word survives where it costs nothing: the VoiceOver label and
    /// the screen it opens.
    private var duplicatesCount: Int? {
        guard let count = UserDefaults.standard.object(forKey: SettingsKeys.duplicateGroupCount) as? Int,
              count > 0
        else { return nil }
        return count
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
    /// Card width. 190 is what the two-line token this replaced already
    /// needed, and it is the number that fits the longest pair the band
    /// actually carries — measured on the phone, "Duplicates · 1 group" came
    /// out as "Dupli… 1 group" at 170. Wider on a regular-width window for
    /// the same reason the cover tiles are bigger there: the band is
    /// horizontal, so width is what a wide screen has to give.
    static let compactWidth: CGFloat = 190
    static let regularWidth: CGFloat = 240

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
        case .places:
            NavigationLink(value: PlacesDestination()) {
                UtilityToken(title: "Places", subtitle: "Browse on a map", systemImage: "map")
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.places) }
        case .trips:
            NavigationLink(value: TripsDestination()) {
                UtilityToken(title: "Trips", subtitle: "Days spent away", systemImage: "airplane")
            }
            .buttonStyle(.plain)
            .contextMenu { pinButton(.trips) }
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

    /// The Memories row: wide cards the user scrolls sideways, each opening
    /// the photos it stands for.
    fileprivate func memoriesSection() -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Memories")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(model.memories) { memory in
                        NavigationLink {
                            PhotoListScreen(
                                title: memory.title,
                                subtitle: memory.subtitle,
                                assetIds: memory.assetIds
                            )
                        } label: {
                            MemoryCard(memory: memory)
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

/// A tile for something that has no cover photo of its own — Places, Trips,
/// Duplicates, Recently Viewed. Same tile, a glyph in the cover well.
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

/// The Duplicates tile, whose second line is the group count of the last scan.
struct DuplicatesToken: View {
    @AppStorage(SettingsKeys.duplicateGroupCount) private var groupCount: Int?

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
}


/// One memory as a wide cover with its title and count burned into the bottom.
/// Same shape as `TripCard` but narrower, because these scroll sideways.
struct MemoryCard: View {
    let memory: Memory

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var cover: UIImage?

    /// Wider and taller as the text grows: a memory card is mostly title and
    /// date, and at accessibility sizes both were being cut in half. It also
    /// grows with the window, on the same terms as the cover tiles beside it
    /// (`DESIGN.md` §10.1d) — it is the same kind of thing.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .headline) private var typeScale = 1.0

    private var size: CGSize {
        let base = AlbumTileMetrics.memorySize(isRegularWidth: horizontalSizeClass == .regular)
        return CGSize(width: base.width * typeScale, height: base.height * typeScale)
    }
    private var width: CGFloat { size.width }
    private var height: CGFloat { size.height }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(memory.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(memory.title), \(memory.subtitle)")
        .task(id: memory.coverAssetId) { await loadCover() }
    }

    private func loadCover() async {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [memory.coverAssetId]).first
        else { return }
        let scale = ActiveDisplay.scale
        let size = CGSize(width: width * scale, height: height * scale)
        cover = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestAlbumCover(for: asset, targetSize: size, allowNetwork: true) { image in
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
