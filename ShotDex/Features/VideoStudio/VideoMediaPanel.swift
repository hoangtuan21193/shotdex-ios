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
    @Environment(\.openURL) private var openURL
    @State private var library: VideoMediaLibrary?
    @State private var tab: Tab = .recents
    /// The album whose grid is open from the Albums tab.
    @State private var openAlbum: VideoMediaLibrary.Album?
    @State private var albums: [VideoMediaLibrary.Album] = []
    /// Search (FS-12.09 §5): the field in the tab row's place, and what it
    /// holds. Session state.
    @State private var isSearching = false
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isQueryFocused: Bool

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
        if isSearching {
            searchRow
        } else if let openAlbum {
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
                        .minimumScaleFactor(0.8)
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
            startSearch()
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
                .minimumScaleFactor(0.8)
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
        case .recents, .albums:
            libraryContent
        case .inVideo:
            VideoInVideoList(model: model, rowHeight: metrics == .pool ? 52 : 56)
        }
    }

    /// Recents and Albums, by what the app may read (FS-12.09 §4): denied
    /// says so and points at Settings; limited lists what was granted under
    /// a row that can grant more; an empty library says it is empty.
    @ViewBuilder
    private var libraryContent: some View {
        switch model.photoLibrary.authorizationState {
        case .denied, .restricted, .notDetermined:
            noAccess
        case .limited, .authorized:
            VStack(spacing: 0) {
                if model.photoLibrary.authorizationState == .limited, tab == .recents, !isSearching, let library {
                    limitedRow(count: library.count)
                }
                if tab == .albums, openAlbum == nil {
                    albumList
                } else if isSearching, let library, case .search = library.source, library.count == 0 {
                    message(VideoStudioCopy.noMatches)
                } else if tab == .recents, let library, library.count == 0, library.revision > 0, library.source == .recents {
                    message(VideoStudioCopy.noPhotosYet)
                } else {
                    grid
                }
            }
        }
    }

    /// Lock · "ShotDex can see the 12 items you chose." · Manage Access…
    private func limitedRow(count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(VideoStudioCopy.limitedAccess(count))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.photoLibrary.presentLimitedLibraryPicker()
            } label: {
                Text(VideoStudioCopy.manageAccess)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: VideoMediaPanelMetrics.tabHeight)
                    .background(tabFill(isOn: true))
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// NF-04's denied state, in the panel: the grid is gone, In Video stays.
    private var noAccess: some View {
        VStack(spacing: 8) {
            Text(VideoStudioCopy.noAccessToPhotos)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(VideoStudioCopy.noAccessMessage)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text(VideoStudioCopy.openSettings)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: VideoMediaPanelMetrics.tabHeight)
                    .background(tabFill(isOn: true))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                },
                onDragBegan: { asset, location, origin, image in
                    model.beginMediaDrag(VideoMediaPick(asset), at: location, from: origin, image: image)
                },
                onDragMoved: { model.moveMediaDrag(to: $0) },
                onDragEnded: { model.endMediaDrag() }
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

    /// The search field, with Cancel at its right — the tab row's place.
    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField(VideoStudioCopy.searchPrompt, text: $query)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isQueryFocused)
                    .onSubmit { runSearch(after: .zero) }
                    .onChange(of: query) { runSearch(after: .milliseconds(350)) }
            }
            .padding(.horizontal, 10)
            .frame(height: VideoMediaPanelMetrics.tabHeight)
            .background(tabFill(isOn: false))
            Button {
                endSearch()
            } label: {
                Text(VideoStudioCopy.cancel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
    }

    private func startSearch() {
        model.mediaShowsInVideo = false
        isSearching = true
        tab = .recents
        openAlbum = nil
        isQueryFocused = true
    }

    private func endSearch() {
        searchTask?.cancel()
        isSearching = false
        query = ""
        isQueryFocused = false
        library?.show(.recents)
    }

    /// Runs the query a beat after the last keystroke (or at once on
    /// Search), on the Library's index; the grid lists what it matched.
    private func runSearch(after delay: Duration) {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                library?.show(.recents)
                return
            }
            let ids = await VideoMediaLibrary.searchIDs(
                text, service: dependencies.searchService, queries: dependencies.libraryQueries
            )
            guard !Task.isCancelled else { return }
            library?.show(.search(ids))
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
        model.mediaShowsInVideo = value == .inVideo
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

/// In Video (FS-12.09 §4): every use of a library item, in timeline
/// order — thumbnail · when it was taken · "Video · clip 2" · "0:03–0:09"
/// · chevron — the row under the playhead lit. A tap jumps there and
/// selects the item.
private struct VideoInVideoList: View {
    @Bindable var model: VideoStudioModel
    let rowHeight: CGFloat
    @State private var assets: [String: PHAsset] = [:]

    var body: some View {
        let rows = model.inVideoRows
        Group {
            if rows.isEmpty {
                Text(VideoStudioCopy.nothingInVideo)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button { model.goToInVideoRow(row) } label: {
                                rowView(row, isCurrent: row.contains(model.currentTime))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: rows.map(\.assetID)) {
            let missing = Set(rows.map(\.assetID)).subtracting(assets.keys)
            guard !missing.isEmpty else { return }
            for asset in PhotoLibraryService.fetchAssets(ids: Array(missing)) {
                assets[asset.localIdentifier] = asset
            }
        }
    }

    private func rowView(_ row: MediaUsage.Row, isCurrent: Bool) -> some View {
        let asset = assets[row.assetID]
        return HStack(spacing: 12) {
            VideoInVideoThumbnail(asset: asset, photoLibrary: model.photoLibrary, serverFile: model.serverFileURL(for: row.assetID))
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.map(VideoMediaPoolFormat.name(for:)) ?? row.assetID.components(separatedBy: "/").last ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(VideoStudioCopy.inVideoKind(row.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(verbatim: row.span)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, VideoMediaPanelMetrics.rowInset)
        .frame(height: rowHeight)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A row's thumbnail: the library item, or a server photo's copy on disk.
private struct VideoInVideoThumbnail: View {
    let asset: PHAsset?
    let photoLibrary: PhotoLibraryService
    let serverFile: URL?
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: asset?.localIdentifier ?? serverFile?.path) {
                if let asset {
                    _ = photoLibrary.requestThumbnail(
                        for: asset,
                        targetSize: CGSize(width: 44 * displayScale, height: 44 * displayScale),
                        resizeMode: .fast,
                        allowNetwork: false
                    ) { result, _ in
                        if let result { image = result }
                    }
                } else if let serverFile {
                    let side = 44 * displayScale
                    image = await Task.detached(priority: .userInitiated) {
                        UIImage(contentsOfFile: serverFile.path)?.preparingThumbnail(of: CGSize(width: side, height: side))
                    }.value
                }
            }
    }
}

/// The Media panel's fixed sizes (FS-12.09 §3).
enum VideoMediaPanelMetrics {
    /// Tabs, Select and the search disc are 30 tall.
    static let tabHeight: CGFloat = 30
    /// Horizontal padding inside a tab: 8, not the boards' 10 — with
    /// Select and Add (3) beside them the phone's row only fits inside its
    /// 12pt insets at 8, and the pool's 236pt row needs 8 too (FS-12.09 §3).
    static let tabPadding: CGFloat = 8
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
