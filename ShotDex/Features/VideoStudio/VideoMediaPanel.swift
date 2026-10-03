import Photos
import SwiftUI

/// Media (FS-12.09): the photo library inside the studio's own panel — the
/// phone's panel, the iPad dock, the Duo's column and cover panel, the iPad
/// pool's Media tab. A tap inserts at the playhead; the system picker is not
/// used here at all (§2).
///
/// Its tab, open album, search and pending selection are session state
/// (§6): closing the panel forgets them.
struct VideoMediaPanel: View {
    @Bindable var model: VideoStudioModel
    @Environment(\.videoMediaGrid) private var metrics
    @Environment(AppDependencies.self) private var dependencies
    @State private var library: VideoMediaLibrary?
    @State private var tab: Tab = .recents
    /// The album whose grid is open from the Albums tab.
    @State private var openAlbum: VideoMediaLibrary.Album?
    @State private var albums: [VideoMediaLibrary.Album] = []

    enum Tab: Hashable { case recents, albums, inVideo }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 10)
            header
                .frame(height: VideoMediaPanelMetrics.tabHeight)
            Color.clear.frame(height: 6)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            Color.clear.frame(height: 2)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: model.photoLibrary.assetChangeToken) { reload() }
        .task(id: model.photoLibrary.collectionChangeToken) {
            if tab == .albums { albums = library?.albums() ?? [] }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let openAlbum {
            HStack(spacing: 6) {
                Button {
                    self.openAlbum = nil
                    library?.show(.recents)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text(VideoStudioCopy.albums).font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: VideoMediaPanelMetrics.tabHeight)
                    .background(tabFill(isOn: false))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.albums)
                Text(openAlbum.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
        } else {
            HStack(spacing: 6) {
                tabButton(.recents, title: VideoStudioCopy.recents)
                tabButton(.albums, title: VideoStudioCopy.albums)
                tabButton(.inVideo, title: VideoStudioCopy.inVideo(MediaUsage.useCount(in: model.recipe)))
                Spacer(minLength: 0)
                Button {
                    model.toggleMediaSelecting()
                } label: {
                    Text(VideoStudioCopy.select)
                        .font(.system(size: 12.5, weight: model.isSelectingMedia ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: VideoMediaPanelMetrics.tabHeight)
                        .background(tabFill(isOn: model.isSelectingMedia))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.isSelectingMedia ? .isSelected : [])
                if let picks = model.mediaSelection {
                    addButton(count: picks.count)
                } else {
                    searchButton
                }
            }
            .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
        }
    }

    /// Add (N): white, black type, in the search button's place while
    /// selecting; dimmed at zero (FS-12.09 §4).
    private func addButton(count: Int) -> some View {
        Button {
            model.addSelectedMedia()
        } label: {
            Text(VideoStudioCopy.addCount(count))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: VideoMediaPanelMetrics.tabHeight)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous).fill(Color.white))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .opacity(count == 0 ? 0.35 : 1)
        .disabled(count == 0)
    }

    private var searchButton: some View {
        Button {
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: VideoMediaPanelMetrics.tabHeight, height: VideoMediaPanelMetrics.tabHeight)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VideoStudioCopy.searchLibrary)
    }

    private func tabButton(_ value: Tab, title: String) -> some View {
        let isOn = tab == value
        return Button {
            select(value)
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: isOn ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, VideoMediaPanelMetrics.tabPadding)
                .frame(height: VideoMediaPanelMetrics.tabHeight)
                .background(tabFill(isOn: isOn))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// White 20 % when on, 6 % when not, `r-sm` (FS-12.09 §3).
    private func tabFill(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(Color.white.opacity(isOn ? 0.20 : 0.06))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .recents:
            grid
        case .albums:
            if openAlbum != nil { grid } else { albumList }
        case .inVideo:
            Color.clear
        }
    }

    @ViewBuilder
    private var grid: some View {
        if let library {
            VideoMediaGridView(
                library: library,
                revision: library.revision,
                metrics: metrics,
                uses: MediaUsage.uses(in: model.recipe),
                pickNumbers: pickNumbers,
                onTap: { asset in
                    if model.isSelectingMedia {
                        model.toggleMediaPick(VideoMediaPick(asset))
                    } else {
                        insert(asset)
                    }
                }
            )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var albumList: some View {
        if albums.isEmpty {
            Text(VideoStudioCopy.noAlbums)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            albumRows
        }
    }

    private var albumRows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    Button {
                        openAlbum = album
                        library?.show(.album(album.id))
                    } label: {
                        VideoMediaAlbumRow(album: album, photoLibrary: model.photoLibrary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The picked items' numbers by library id.
    private var pickNumbers: [String: Int] {
        Dictionary(
            (model.mediaSelection ?? []).enumerated().map { ($1.assetID, $0 + 1) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func select(_ value: Tab) {
        tab = value
        openAlbum = nil
        library?.show(.recents)
        if value == .albums { albums = library?.albums() ?? [] }
    }

    private func reload() {
        let library = library ?? VideoMediaLibrary(photoLibrary: model.photoLibrary)
        library.reload()
        self.library = library
        if tab == .albums { albums = library.albums() }
    }

    /// A tap: in at the playhead. A RAW this iOS cannot read asks the
    /// question it asks at the door first (FS-03.04b AC-18).
    private func insert(_ asset: PHAsset) {
        let pick = VideoMediaPick(asset)
        let unreadable = dependencies.unsupportedRAWIndex.assetIds
        guard unreadable.contains(pick.assetID) else {
            model.insertMedia([pick])
            return
        }
        Task { @MainActor in
            guard let kept = await UnsupportedRAWBatchPrompt.resolve([asset], unreadable: unreadable),
                  !kept.isEmpty
            else { return }
            model.insertMedia([pick])
        }
    }
}

/// The Media panel's fixed sizes (FS-12.09 §3).
enum VideoMediaPanelMetrics {
    /// Tabs, Select and the search disc are 30 tall.
    static let tabHeight: CGFloat = 30
    /// Horizontal padding inside a tab: 10 on the phone's board.
    static let tabPadding: CGFloat = 10
    /// The row's inset from the panel's edges.
    static let rowInset: CGFloat = 12
    /// One album row.
    static let albumRowHeight: CGFloat = 56
}

/// One album in the Albums tab: cover · name · how many items.
private struct VideoMediaAlbumRow: View {
    let album: VideoMediaLibrary.Album
    let photoLibrary: PhotoLibraryService
    @Environment(\.displayScale) private var displayScale
    @State private var cover: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .overlay {
                    if let cover { Image(uiImage: cover).resizable().scaledToFill() }
                }
                .frame(width: 44, height: 44)
                .clipped()
            Text(album.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: "\(album.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
        .frame(height: VideoMediaPanelMetrics.albumRowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .onAppear {
            guard cover == nil, let asset = album.cover else { return }
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: 44 * displayScale, height: 44 * displayScale),
                resizeMode: .fast,
                allowNetwork: false
            ) { image, _ in
                if let image { cover = image }
            }
        }
    }
}

private struct VideoMediaGridKey: EnvironmentKey {
    static let defaultValue = VideoMediaGridMetrics.phone
}

extension EnvironmentValues {
    /// The Media grid's shape for the window the studio is drawn in
    /// (FS-12.09 §3). Each layout sets its own.
    var videoMediaGrid: VideoMediaGridMetrics {
        get { self[VideoMediaGridKey.self] }
        set { self[VideoMediaGridKey.self] = newValue }
    }
}

extension VideoMediaPick {
    /// A library item as the Media panel adds it.
    init(_ asset: PHAsset) {
        let isVideo = asset.mediaType == .video
        self.init(assetID: asset.localIdentifier, kind: isVideo ? .video : .photo, duration: isVideo ? asset.duration : nil)
    }
}
