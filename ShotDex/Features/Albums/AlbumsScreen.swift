import Photos
import SwiftUI

/// Collections tab: On This Day hero, then horizontally-scrolling token
/// grids (up to 3 rows) for smart albums, My Albums, and Shared Albums.
struct AlbumsScreen: View {
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
    @State private var editingSmartAlbum: SmartAlbum?
    @State private var namingRequest: NamingRequest?
    @State private var enteredName = ""
    @State private var deletionRequest: DeletionRequest?

    /// A pending "type a name" alert — creating an album or folder, or
    /// renaming one. One piece of state for all four, because they differ only
    /// in the title and what happens on confirm.
    struct NamingRequest: Identifiable {
        enum Kind {
            case newAlbum
            case newFolder
            case renameAlbum(AlbumItem)
            case renameFolder(AlbumsModel.FolderItem)
        }

        let id = UUID()
        let kind: Kind

        var title: String {
            switch kind {
            case .newAlbum: String(localized: "New Album")
            case .newFolder: String(localized: "New Folder")
            case .renameAlbum: String(localized: "Rename Album")
            case .renameFolder: String(localized: "Rename Folder")
            }
        }

        var confirmTitle: String {
            switch kind {
            case .newAlbum, .newFolder: String(localized: "Create")
            case .renameAlbum, .renameFolder: String(localized: "Rename")
            }
        }

        var currentName: String {
            switch kind {
            case .newAlbum, .newFolder: ""
            case .renameAlbum(let album): album.title
            case .renameFolder(let folder): folder.title
            }
        }
    }

    /// A pending delete, confirmed before it happens. Deleting an album never
    /// deletes photos — the message says so, because that is the one thing a
    /// user needs to be sure of here.
    struct DeletionRequest: Identifiable {
        enum Target {
            case album(AlbumItem)
            case folder(AlbumsModel.FolderItem)
        }

        let id = UUID()
        let target: Target

        var title: String {
            switch target {
            case .album(let album): String(localized: "Delete “\(album.title)”?")
            case .folder(let folder): String(localized: "Delete “\(folder.title)”?")
            }
        }

        var message: String {
            switch target {
            case .album:
                String(localized: "The photos stay in your library.")
            case .folder:
                String(localized: "The albums inside move back to My Albums.")
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
                        Label("New Album", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        isCreatingSmartAlbum = true
                    } label: {
                        Label("New Smart Album", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        namingRequest = NamingRequest(kind: .newFolder)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .tint(.primary)
                .accessibilityLabel("New album, smart album or folder")
            }
        }
        // `assetChangeToken`, not `libraryChangeToken`: the album list only
        // moves on insert/remove/move. Content-only notifications (PhotoKit
        // caching a rendition, a favorite toggle) used to rebuild the whole
        // snapshot, and iCloud streaming during an index run fires those about
        // once a second.
        .task(id: photoLibrary.assetChangeToken) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            if model.dependencies == nil { model.dependencies = dependencies }
            model.load(forAssetToken: photoLibrary.assetChangeToken)
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

    private var albumGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if photoLibrary.authorizationState == .limited {
                    LimitedAccessBanner {
                        photoLibrary.presentLimitedLibraryPicker()
                    }
                    .padding(.top, 4)
                }

                NavigationLink(value: OnThisDayDestination()) {
                    OnThisDayCard(
                        count: model.onThisDayCount,
                        coverAsset: model.onThisDayCover
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if !model.memories.isEmpty {
                    memoriesSection()
                }

                if !(model.smartQueryAlbums.isEmpty && model.smartAlbums.isEmpty) {
                    smartAlbumsSection()
                }

                if !model.mediaTypeAlbums.isEmpty {
                    albumTokenSection(title: "Media Types", albums: model.mediaTypeAlbums)
                }

                if !model.folders.isEmpty {
                    foldersSection()
                }

                if !model.userAlbums.isEmpty {
                    albumTokenSection(title: "My Albums", albums: model.userAlbums)
                }

                if !model.sharedAlbums.isEmpty {
                    albumTokenSection(title: "Shared Albums", albums: model.sharedAlbums)
                }

                utilitiesSection()

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
        }
    }

    /// "Move to Folder" — the only way an album gets into a folder, since a
    /// folder created here starts empty.
    @ViewBuilder
    private func moveToFolderMenu(_ album: AlbumItem) -> some View {
        if !model.folders.isEmpty {
            Menu {
                ForEach(model.folders) { folder in
                    Button(folder.title) { model.move(album, to: folder) }
                }
                if model.folders.contains(where: { folder in
                    folder.albums.contains { $0.id == album.id }
                }) {
                    Divider()
                    Button("Move Out of Folder") { model.move(album, to: nil) }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
    }

    private func apply(_ request: NamingRequest) {
        let name = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        namingRequest = nil
        guard !name.isEmpty else { return }
        switch request.kind {
        case .newAlbum: model.createAlbum(named: name)
        case .newFolder: model.createFolder(named: name)
        case .renameAlbum(let album): model.rename(album, to: name)
        case .renameFolder(let folder): model.rename(folder, to: name)
        }
    }

    private func confirmDelete(_ request: DeletionRequest) {
        deletionRequest = nil
        switch request.target {
        case .album(let album): model.delete(album)
        case .folder(let folder): model.delete(folder)
        }
    }

    /// Optional header + horizontal-scrolling grid of uniform album tokens
    /// (cover thumbnail + name + count). Fills up to 3 rows column-major
    /// before scrolling right, like the iOS Photos pinned-collections grid.
    /// Used for smart albums (no header), "My Albums", and "Shared Albums".
    private func albumTokenSection(title: String?, albums: [AlbumItem]) -> some View {
        // Grow rows only as albums accumulate (~3 per column), capped at 3,
        // so a handful of albums stays 1–2 rows tall instead of a stubby
        // 3-row block.
        let rowCount = max(1, min(3, (albums.count + 2) / 3))
        let rows = Array(
            repeating: GridItem(.fixed(AlbumToken.height), spacing: 8),
            count: rowCount
        )
        return VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(albums) { album in
                        NavigationLink(value: album.id) {
                            AlbumToken(album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // System albums (Recents, Videos, …) reject both,
                            // so the menu is only offered on the user's own.
                            if album.group == .user {
                                Button {
                                    namingRequest = NamingRequest(kind: .renameAlbum(album))
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                moveToFolderMenu(album)
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
        let total = model.smartQueryAlbums.count + model.smartAlbums.count
        let rowCount = max(1, min(3, (total + 2) / 3))
        let rows = Array(
            repeating: GridItem(.fixed(AlbumToken.height), spacing: 8),
            count: rowCount
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("Smart Albums")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(model.smartQueryAlbums) { item in
                        NavigationLink(value: SmartAlbumDestination(id: item.album.id)) {
                            SmartAlbumToken(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
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

/// Utilities that act on the library rather than browse it — today only the
/// duplicate finder. Same token footprint as the album grids so the section
/// lines up with them.
extension AlbumsScreen {
    fileprivate func utilitiesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Utilities")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(AlbumToken.height), spacing: 8)], spacing: 8) {
                    NavigationLink(value: DuplicatesDestination()) {
                        DuplicatesToken()
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: PlacesDestination()) {
                        UtilityToken(
                            title: "Places",
                            subtitle: "Browse on a map",
                            systemImage: "map"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: TripsDestination()) {
                        UtilityToken(
                            title: "Trips",
                            subtitle: "Days spent away",
                            systemImage: "airplane"
                        )
                    }
                    .buttonStyle(.plain)

                    // Hidden and Unable to Upload: library housekeeping rather
                    // than browsing, so they sit beside Duplicates the way
                    // Photos groups its own utilities.
                    ForEach(model.utilityAlbums) { album in
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

extension AlbumsScreen {
    /// The Memories row: wide cards the user scrolls sideways, each opening
    /// the photos it stands for.
    fileprivate func memoriesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memories")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
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

    /// One row per folder, each showing the albums it holds. Folders are rare
    /// and usually few, so they are listed rather than squeezed into the same
    /// horizontal token grid as everything else.
    fileprivate func foldersSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders")
                .font(.title2.bold())
                .padding(.horizontal)

            ForEach(model.folders) { folder in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(folder.title)
                            .font(.headline)
                    }
                    .padding(.horizontal)
                    .contextMenu {
                        Button {
                            namingRequest = NamingRequest(kind: .renameFolder(folder))
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deletionRequest = DeletionRequest(target: .folder(folder))
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }

                    if folder.albums.isEmpty {
                        Text("Empty. Move an album here from its own menu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(folder.albums) { album in
                                    NavigationLink(value: album.id) {
                                        AlbumToken(album: album)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            namingRequest = NamingRequest(kind: .renameAlbum(album))
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        moveToFolderMenu(album)
                                        Button(role: .destructive) {
                                            deletionRequest = DeletionRequest(target: .album(album))
                                        } label: {
                                            Label("Delete Album", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        }
    }
}

/// Generic utility token: an SF Symbol where an album would show a cover, plus
/// a one-line subtitle. Same footprint as `AlbumToken` so the Utilities row
/// lines up with the album grids above it.
struct UtilityToken: View {
    let title: String
    let subtitle: String
    let systemImage: String

    private let thumbSide: CGFloat = 44
    private let tokenWidth: CGFloat = 190

    var body: some View {
        HStack(spacing: 8) {
            Color(.tertiarySystemBackground)
                .frame(width: thumbSide, height: thumbSide)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: tokenWidth, height: AlbumToken.height, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

/// Token for the Duplicates utility: glyph in place of a cover, and the group
/// count of the last grouping (or an invitation to scan) as the subtitle.
struct DuplicatesToken: View {
    @AppStorage(SettingsKeys.duplicateGroupCount) private var groupCount: Int?

    private let thumbSide: CGFloat = 44
    private let tokenWidth: CGFloat = 190

    var body: some View {
        HStack(spacing: 8) {
            Color(.tertiarySystemBackground)
                .frame(width: thumbSide, height: thumbSide)
                .overlay {
                    Image(systemName: "square.on.square")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicates")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: tokenWidth, height: AlbumToken.height, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duplicates, \(subtitle)")
    }

    private var subtitle: String {
        guard let groupCount else { return "Scan library" }
        return groupCount == 1 ? "1 group" : "\(groupCount) groups"
    }
}

/// Navigation value for a user-created smart album's detail screen. Distinct
/// type from `AlbumItem.ID` (also `String`) so it routes to
/// `SmartAlbumDetailScreen` rather than the existing `AlbumItem.ID` destination.
struct SmartAlbumDestination: Hashable {
    let id: String
}

/// Fixed-size token: small square cover thumbnail on the left, album title
/// and photo count on the right. Styled after the iOS Photos media-type
/// rows but laid out as a horizontally scrolling token.
struct AlbumToken: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let album: AlbumItem

    @State private var cover: UIImage?
    /// Assets warmed for this album's detail grid, so caching is cancelled
    /// again when the token scrolls away.
    @State private var prewarmedAssets: [PHAsset] = []
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3

    /// Fixed outer height so grid rows align.
    static let height: CGFloat = 60

    private let thumbSide: CGFloat = 44
    private let tokenWidth: CGFloat = 190

    var body: some View {
        HStack(spacing: 8) {
            Color(.tertiarySystemBackground)
                .frame(width: thumbSide, height: thumbSide)
                .overlay {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: album.symbolName ?? "photo.on.rectangle")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text("\(album.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: tokenWidth, height: Self.height, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .onAppear {
            loadCover()
            prewarmDetailGrid()
        }
        .onDisappear(perform: stopPrewarmingDetailGrid)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.count) photos")
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
        let scale = ActiveDisplay.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: thumbSide * scale, height: thumbSide * scale),
            allowNetwork: false
        ) { image in
            if let image {
                cover = image
            }
        }
    }
}

/// FilterToken for a user-created smart album (saved filter): cover thumbnail of the
/// first matching photo (funnel glyph when empty), the album name, and its
/// live match count. Same footprint as `AlbumToken` so the two token grids line
/// up.
struct SmartAlbumToken: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let item: SmartAlbumTokenItem

    @State private var cover: UIImage?

    private let thumbSide: CGFloat = 44
    private let tokenWidth: CGFloat = 190

    var body: some View {
        HStack(spacing: 8) {
            Color(.tertiarySystemBackground)
                .frame(width: thumbSide, height: thumbSide)
                .overlay {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.album.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text("\(item.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: tokenWidth, height: AlbumToken.height, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .onAppear(perform: loadCover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.album.name), \(item.count) photos")
    }

    private func loadCover() {
        guard cover == nil, let asset = item.coverAsset else { return }
        let scale = ActiveDisplay.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: thumbSide * scale, height: thumbSide * scale),
            allowNetwork: false
        ) { image in
            if let image {
                cover = image
            }
        }
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
        Color(.secondarySystemBackground)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
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
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(cover == nil ? Color(.secondaryLabel) : .white)
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            // `coverAsset` is filled asynchronously by AlbumsModel, so
            // onAppear alone can miss it when this card appears first.
            .task(id: coverAsset?.localIdentifier) {
                loadCover()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("On This Day, \(count) photos from previous years")
    }

    private var subtitle: String {
        let date = Date.now.formatted(.dateTime.month(.wide).day())
        return count == 0
            ? "\(date) · No photos in previous years"
            : "\(date) · \(count) photos from previous years"
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

/// One memory as a wide cover with its title and count burned into the bottom.
/// Same shape as `TripCard` but narrower, because these scroll sideways.
struct MemoryCard: View {
    let memory: Memory

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var cover: UIImage?

    private static let width: CGFloat = 260
    private static let height: CGFloat = 150

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
            .frame(width: Self.width, height: Self.height)
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
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(memory.title), \(memory.subtitle)")
        .task(id: memory.coverAssetId) { await loadCover() }
    }

    private func loadCover() async {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [memory.coverAssetId]).first
        else { return }
        let scale = ActiveDisplay.scale
        let size = CGSize(width: Self.width * scale, height: Self.height * scale)
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
