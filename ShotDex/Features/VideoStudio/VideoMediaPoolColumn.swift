import Photos
import SwiftUI
import ShotDexKit

/// The media pool: the library standing open beside the stage, the way every
/// desktop-shaped NLE has it — Resolve's Media pool, Final Cut's browser,
/// LumaFusion's library drawer.
///
/// On a phone media arrives through `PHPickerViewController`, a modal that
/// covers the project to add one clip and then goes away. That is the right
/// shape for a 393pt screen and the wrong one for a 1200pt window, where the
/// column costs nothing the stage was using and a clip is one tap or one drag
/// from the timeline instead of four taps through a sheet.
///
/// It reads the library directly rather than through `LibraryQueries`: the
/// pool wants what PhotoKit has *right now* in one fetch, unfiltered by the
/// index, and the studio already owns `PHAsset`s everywhere else.
struct VideoMediaPoolColumn: View {
    @Bindable var model: VideoStudioModel
    let photoLibrary: PhotoLibraryService
    let width: CGFloat
    /// The imported-music library, for the Music tab.
    @ObservedObject var importedMusic: ImportedMusicStore
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// Closes the column. The same control that opened it in the top band.
    let onClose: () -> Void
    /// Opens the sticker picker, for a sticker that is not in the grid.
    let onChooseSticker: () -> Void
    /// Imports a music file from Files.
    let onImportMusic: () -> Void
    /// Adds one library photo as a sticker overlay.
    let onAddSticker: (PHAsset) -> Void
    /// Adds a caption, optionally in a font picked from the Text tab.
    let onAddText: (OverlayFontChoice?) -> Void

    @State private var tab: Tab = .media
    /// Bumped by the header's search button; the Media panel opens its field.
    @State private var searchRequest = 0
    @State private var assets: [PHAsset] = []

    /// How many photos the Stickers tab holds at once. The Media tab has no
    /// cap: it is the Media panel, over a lazy fetch (FS-12.09 §2).
    private static let capacity = 400

    private typealias Pool = VideoStudioMetrics.Pool

    var body: some View {
        VStack(spacing: 0) {
            header
            VideoDeskSegmented(
                items: Tab.allCases.map { ($0, $0.title, "poolTab.\($0.rawValue)") },
                selection: Binding(get: { tab }, set: { new in withAnimation(EditorTheme.animation) { tab = new } }),
                label: Text(verbatim: "Pool")
            )
            .padding(.horizontal, Pool.inset)
            .padding(.top, Pool.segmentedTop)
            .padding(.bottom, Pool.contentGap)
            content
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        // The pool floats: the editor's dark glass, its stroke and a soft
        // shadow, radius 22 (FS-12.03 §2, board IL1_Main).
        .clipShape(RoundedRectangle(cornerRadius: VideoStudioDeskGeometry.poolCornerRadius, style: .continuous))
        .editorGlass(cornerRadius: VideoStudioDeskGeometry.poolCornerRadius, tint: EditorTheme.sidebarGlass)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Media Pool", comment: "Video Studio: shows or hides the library column"))
        .task(id: photoLibrary.libraryChangeToken) { reload() }
        .onChange(of: tab) { reload() }
    }

    // MARK: Bands

    /// "Library" · Select · Search Library · Hide Media (FS-12.03b §1,
    /// FS-12.09 §3). Select and search act on the Media tab, so from another
    /// tab they open it first.
    private var header: some View {
        HStack(spacing: 0) {
            Text(VideoStudioCopy.library)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                tab = .media
                model.toggleMediaSelecting()
            } label: {
                Text(VideoStudioCopy.select)
                    .font(.system(size: 17, weight: model.isSelectingMedia ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .frame(width: Pool.selectWidth, height: Pool.headerHeight)
                    .background(Capsule().fill(model.isSelectingMedia ? VideoStudioMetrics.openCellFill : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.isSelectingMedia ? .isSelected : [])
            headerButton("magnifyingglass") {
                tab = .media
                searchRequest += 1
            }
            .accessibilityLabel(VideoStudioCopy.searchLibrary)
            headerButton("sidebar.leading", action: onClose)
                .accessibilityLabel(Text("Hide Media", comment: "Video Studio: closes the library column"))
        }
        .padding(.leading, Pool.titleLeading)
        .padding(.trailing, Pool.headerTrailing)
        .padding(.top, Pool.headerTop)
        .frame(height: Pool.headerTop + Pool.headerHeight, alignment: .bottom)
    }

    /// A 44pt glyph button in the pool's title row.
    private func headerButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Pool.headerHeight, height: Pool.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .media: VideoMediaPanel(model: model, isPoolColumn: true, searchRequest: searchRequest)
        case .stickers: libraryContent
        case .text: textContent
        case .music: musicContent
        }
    }

    /// The Text tab (FS-12.03b §1): the Text tool's content, the same view
    /// the phone and the Duo show in their Text panel.
    private var textContent: some View {
        VideoTextToolContent(
            model: model, style: .pool,
            onAddText: onAddText,
            onAutoCaptions: { Task { await model.startAutoCaptions() } }
        )
    }

    /// The Music tab is the Music panel itself (FS-12.03b §1): Video sound,
    /// Add Music from Files…, My Music — one place, one set of names.
    private var musicContent: some View {
        VideoMusicPanelContent(model: model, importedMusic: importedMusic, onImport: onImportMusic, style: .pool)
    }

    /// One full-width row that opens something rather than inserting it.
    private func actionRow(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 30, height: 30)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var libraryContent: some View {
        if assets.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22))
                    .foregroundStyle(EditorTheme.dimText)
                Text("Nothing to add", comment: "Video Studio media pool: empty state title")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                Text("Photos and videos in your library appear here.", comment: "Video Studio media pool: empty state body")
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.dimText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    // A sticker that is not among the most recent `capacity`
                    // items comes through the sticker picker.
                    actionRow(
                        systemImage: "photo.badge.plus",
                        title: String(localized: "Choose a Sticker…", comment: "Video Studio media pool: opens the picker for a sticker image"),
                        action: onChooseSticker
                    )
                    gridBody
                }
            }
            .scrollIndicators(.automatic)
        }
    }

    private var gridBody: some View {
        // Stickers: two columns across the pool's 294pt, 8 apart.
        let cell = (width - Pool.inset * 2 - Pool.stickerGap) / 2
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cell), spacing: Pool.stickerGap), count: 2),
            spacing: Pool.stickerGap
        ) {
            ForEach(assets, id: \.localIdentifier) { asset in
                VideoMediaPoolCell(
                    asset: asset,
                    photoLibrary: photoLibrary,
                    width: cell,
                    onAdd: { append(asset) }
                )
            }
        }
        .padding(.horizontal, Pool.inset)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    /// A tap on the Stickers tab's grid lays the photo over the frame.
    private func append(_ asset: PHAsset) {
        onAddSticker(asset)
    }

    private func reload() {
        guard tab == .stickers else { return }
        guard photoLibrary.authorizationState.canReadLibrary else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        // A sticker is drawn over the frame, so a clip cannot be one.
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = Self.capacity
        let result = PHAsset.fetchAssets(with: options)
        var collected: [PHAsset] = []
        collected.reserveCapacity(min(result.count, Self.capacity))
        result.enumerateObjects { asset, index, stop in
            collected.append(asset)
            if index + 1 >= Self.capacity { stop.pointee = true }
        }
        assets = collected
    }

    // MARK: Column state

    /// What the column is listing, and what a tap on it inserts.
    enum Tab: String, CaseIterable, Identifiable {
        /// In the board's order: Media · Text · Stickers · Music
        /// (FS-12.03b §1). The look is the inspector's, not a tab's.
        case media, text, stickers, music
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .media: "photo.stack"
            case .stickers: "photo.badge.plus"
            case .text: "textformat"
            case .music: "music.note"
            }
        }

        var title: String {
            switch self {
            case .media: String(localized: "Media", comment: "Video Studio media pool tab: photos and videos to add as clips")
            case .stickers: String(localized: "Stickers", comment: "Video Studio media pool tab: photos to add as an overlay")
            case .text: String(localized: "Text", comment: "Video Studio media pool tab: captions to add over the frame")
            case .music: String(localized: "Music", comment: "Video Studio media pool tab: audio to add as a music bed")
            }
        }
    }
}

// MARK: - Cells

/// One thumbnail in the pool's grid. Tapping appends it to the Video track;
/// dragging carries the same payload the library grid does, so it can be
/// dropped on the timeline — or out of ShotDex entirely.
private struct VideoMediaPoolCell: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService
    let width: CGFloat
    let onAdd: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var height: CGFloat { (width * 9 / 16).rounded() }

    var body: some View {
        VStack(spacing: 3) {
            Button(action: onAdd) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(EditorTheme.control)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(alignment: .bottomLeading) { badge }
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(EditorTheme.trackBorder, lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(VideoMediaPoolFormat.name(for: asset))
                .font(.system(size: 9.5))
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VideoMediaPoolFormat.accessibilityLabel(for: asset))
        .accessibilityHint(Text("Adds this to the end of the video track", comment: "Video Studio media pool: what tapping an item does"))
        .onDrag { PhotoDragItem.provider(for: asset) }
        .onAppear { load() }
    }

    @ViewBuilder
    private var badge: some View {
        if asset.mediaType == .video {
            HStack(spacing: 2) {
                Image(systemName: "play.fill").font(.system(size: 7))
                Text(VideoMediaPoolFormat.duration(asset.duration))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(.black.opacity(0.6)))
            .padding(3)
        }
    }

    private func load() {
        guard image == nil else { return }
        let target = CGSize(width: width * displayScale, height: height * displayScale)
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: target,
            resizeMode: .fast,
            allowNetwork: false
        ) { result, _ in
            if let result { image = result }
        }
    }
}

/// The strings the pool prints. Kept in one place because the grid cell, the
/// row and the VoiceOver label all name the same asset and must agree.
enum VideoMediaPoolFormat {
    /// The capture date, not the file name: reading a file name off a
    /// `PHAsset` costs a `PHAssetResource` fetch per item, and "IMG_4821"
    /// tells a photographer less than the day they shot it anyway.
    static func name(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else {
            return String(localized: "No Date", comment: "Video Studio media pool: an item whose capture date the library does not carry")
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func subtitle(for asset: PHAsset) -> String {
        asset.mediaType == .video
            ? duration(asset.duration)
            : String(localized: "Photo", comment: "Video Studio media pool: the kind of a still item")
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A Media cell, for VoiceOver (FS-12.09 §7): "Video, 0:06, in this
    /// video" — a video by its length, a photo by when it was taken, and
    /// whether it is already used.
    static func mediaCellLabel(isVideo: Bool, duration: Double, name: String, uses: Int) -> String {
        let base = isVideo
            ? String(localized: "Video, \(Self.duration(duration))", table: VideoStudioCopy.table, comment: "Video Studio Media panel: VoiceOver label of a video cell — its length")
            : String(localized: "Photo, \(name)", table: VideoStudioCopy.table, comment: "Video Studio Media panel: VoiceOver label of a photo cell — when it was taken")
        return uses > 0 ? "\(base), \(VideoStudioCopy.inThisVideo)" : base
    }

    static func accessibilityLabel(for asset: PHAsset) -> String {
        asset.mediaType == .video
            ? String(
                localized: "Video, \(name(for: asset)), \(duration(asset.duration))",
                comment: "Video Studio media pool: VoiceOver label for a clip — kind, capture date, length"
            )
            : String(
                localized: "Photo, \(name(for: asset))",
                comment: "Video Studio media pool: VoiceOver label for a still — kind, capture date"
            )
    }
}
