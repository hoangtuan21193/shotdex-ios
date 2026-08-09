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
                Button {
                    isCreatingSmartAlbum = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Smart Album")
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
        .sheet(isPresented: $isCreatingSmartAlbum) {
            SmartAlbumEditorSheet(existing: nil, dependencies: dependencies) {
                model.load()
            }
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

                if !(model.smartQueryAlbums.isEmpty && model.smartAlbums.isEmpty) {
                    smartAlbumsSection()
                }

                if !model.userAlbums.isEmpty {
                    albumTokenSection(title: "My Albums", albums: model.userAlbums)
                }

                if !model.sharedAlbums.isEmpty {
                    albumTokenSection(title: "Shared Albums", albums: model.sharedAlbums)
                }

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
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
                        Image(systemName: "photo.on.rectangle")
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
        let scale = UIScreen.main.scale
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
        let scale = UIScreen.main.scale
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
