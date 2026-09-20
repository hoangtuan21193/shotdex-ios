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
    /// Opens the full system picker — the pool holds only the most recent
    /// `capacity` items, so this is the way to anything older.
    let onBrowseAll: () -> Void
    /// Opens the sticker picker, for a sticker that is not in the grid.
    let onChooseSticker: () -> Void
    /// Imports a music file from Files.
    let onImportMusic: () -> Void
    /// Adds one library photo as a sticker overlay.
    let onAddSticker: (PHAsset) -> Void
    /// Adds a caption, optionally in a font picked from the Text tab.
    let onAddText: (OverlayFontChoice?) -> Void

    @State private var tab: Tab = .media
    @State private var lookThumbnails = VideoFilterThumbnails()
    @State private var source: Source = .all
    @State private var order: Order = .newest
    @State private var presentation: Presentation = .grid
    @State private var assets: [PHAsset] = []

    /// How many assets the pool holds at once. A 55,000-photo library fetched
    /// whole is a `PHFetchResult` walk on the main actor before the first
    /// thumbnail is asked for; the pool is a place to reach for the last few
    /// hundred things you shot, not a second library browser.
    private static let capacity = 400

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            if tab == .media { toolRow }
            Divider().overlay(EditorTheme.panelDivider)
            binLabel
            content
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .trailing) {
            Rectangle().fill(EditorTheme.panelDivider).frame(width: 1)
        }
        .task(id: photoLibrary.libraryChangeToken) { reload() }
        .onChange(of: source) { reload() }
        .onChange(of: order) { reload() }
        .onChange(of: tab) { reload() }
    }

    // MARK: Bands

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EditorTheme.accent)
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: AppTheme.Size.minTouch, height: 28)
                    .videoHitTarget(drawnHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide Media", comment: "Video Studio: closes the library column"))
        }
        .padding(.horizontal, 12)
        .frame(height: VideoStudioMetrics.mediaPoolHeaderHeight)
    }

    /// The one row that says what this column is for right now — the same
    /// job Resolve's Media / Titles / Effects tabs do, and the same rule: the
    /// tab decides **what a tap inserts**, not just what is listed. Media
    /// adds a clip, Stickers adds an overlay, Music adds a bed.
    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { candidate in
                Button {
                    withAnimation(EditorTheme.animation) { tab = candidate }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: candidate.systemImage)
                            .font(.system(size: 13, weight: .medium))
                        Text(candidate.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(candidate == tab ? EditorTheme.accent : EditorTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(candidate == tab ? EditorTheme.accent.opacity(0.14) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A stable handle for the UI driver: "Text" and "Music" also
                // name a timeline lane and an add-button, so a label match
                // cannot tell them apart.
                .accessibilityIdentifier("poolTab.\(candidate.rawValue)")
                .accessibilityLabel(candidate.title)
                .accessibilityAddTraits(candidate == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: VideoStudioMetrics.mediaPoolTabStripHeight)
    }

    private var toolRow: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("Show", selection: $source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                poolGlyph("line.3.horizontal.decrease.circle", isActive: source != .all)
            }
            .accessibilityLabel(Text("Filter Media", comment: "Video Studio media pool: picks which media the column lists"))

            Menu {
                Picker("Sort", selection: $order) {
                    ForEach(Order.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                poolGlyph("arrow.up.arrow.down.circle", isActive: order != .newest)
            }
            .accessibilityLabel(Text("Sort Media", comment: "Video Studio media pool: picks the order the column lists media in"))

            Spacer(minLength: 0)

            ForEach(Presentation.allCases) { mode in
                Button { presentation = mode } label: {
                    poolGlyph(mode.systemImage, isActive: presentation == mode)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.title))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: VideoStudioMetrics.mediaPoolToolRowHeight)
    }

    private func poolGlyph(_ name: String, isActive: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(isActive ? EditorTheme.accent : EditorTheme.secondaryText)
            .frame(width: AppTheme.Size.minTouch, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? EditorTheme.accent.opacity(0.14) : .clear)
                    .padding(.horizontal, 7)
            )
            .videoHitTarget(drawnHeight: 28)
    }

    /// Resolve labels the open bin above its grid; here the bin is whichever
    /// slice of the library the filter is showing, and the count is the thing
    /// a photographer actually checks before scrolling.
    private var binLabel: some View {
        HStack(spacing: 6) {
            Text(tab == .media ? source.title : tab.binTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text(binCount)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(EditorTheme.dimText)
            Spacer(minLength: 0)
            if tab == .media { insertModeMenu }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(EditorTheme.stickyHeader)
    }

    private var binCount: String {
        switch tab {
        case .media, .stickers: countText
        case .text: "\(model.fontRecents.count)"
        case .music: "\(importedMusic.tracks.count)"
        case .effects: "\(PhotoFilter.allCases.count)"
        }
    }

    /// Where a tap lands the clip. Resolve names this on the buttons
    /// themselves (Smart Insert / Append at End / Place on Top); with one
    /// video track there are two honest choices, so they live in a menu on
    /// the bin row rather than eating two more controls.
    private var insertModeMenu: some View {
        Menu {
            Picker("Insert", selection: Binding(
                get: { model.mediaInsertMode },
                set: { model.mediaInsertMode = $0 }
            )) {
                ForEach(VideoStudioModel.MediaInsertMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.mediaInsertMode.systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(model.mediaInsertMode == .appendAtEnd
                     ? String(localized: "End", comment: "Video Studio media pool: short label for Append at End")
                     : String(localized: "Playhead", comment: "Video Studio media pool: short label for Insert at Playhead"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(EditorTheme.accent)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(EditorTheme.accent.opacity(0.14))
            )
        }
        .accessibilityLabel(Text("Where new media lands", comment: "Video Studio media pool: picks append-at-end or insert-at-playhead"))
        .accessibilityValue(model.mediaInsertMode.title)
    }

    private var countText: String {
        assets.count >= Self.capacity
            ? String(localized: "\(Self.capacity)+", comment: "Video Studio media pool: the column is showing its first N items and the library holds more")
            : "\(assets.count)"
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .media, .stickers: libraryContent
        case .text: textContent
        case .music: musicContent
        case .effects: effectsContent
        }
    }

    /// The Text tab. Resolve's Titles tab is a template gallery you drag
    /// from; ShotDex has no title templates, but it does keep the fonts the
    /// user has reached for — so the list is those, and picking one adds a
    /// caption already wearing it. The plain "Add Text" row is first, for
    /// when the font is not the point.
    private var textContent: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                actionRow(
                    systemImage: "textformat",
                    title: String(localized: "Add Text", comment: "Video Studio media pool: adds a caption in the last-used font"),
                    action: { onAddText(nil) }
                )
                if model.fontRecents.isEmpty {
                    Text("Fonts you use appear here, ready to reuse.", comment: "Video Studio media pool: empty state for the text tab")
                        .font(.system(size: 11))
                        .foregroundStyle(EditorTheme.dimText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                ForEach(model.fontRecents) { font in
                    Button { onAddText(font) } label: {
                        HStack(spacing: 8) {
                            Text("Aa")
                                .font(Self.preview(for: font))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(EditorTheme.control)
                                )
                            Text(font.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(EditorTheme.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Adds a caption in this font", comment: "Video Studio media pool: what tapping a font row does"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    /// The Effects tab — Resolve's own name for the library you pick a look
    /// out of. Tapping applies it to the project; how strongly is a slider,
    /// and a slider belongs in the inspector, not in a library.
    private var effectsContent: some View {
        let cell = VideoStudioMetrics.mediaPoolCellWidth(columnWidth: width)
        return ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(cell), spacing: VideoStudioMetrics.mediaPoolCellSpacing),
                    count: VideoStudioMetrics.mediaPoolColumnCount(columnWidth: width)
                ),
                spacing: VideoStudioMetrics.mediaPoolCellSpacing
            ) {
                ForEach(PhotoFilter.allCases) { filter in
                    Button { model.setFilter(filter) } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(EditorTheme.control)
                                .overlay {
                                    // The frame the user is looking at, under
                                    // this look — not a glyph that is the
                                    // same for all forty-nine.
                                    if let preview = lookThumbnails.images[filter] {
                                        Image(uiImage: preview)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "camera.filters")
                                            .font(.system(size: 15))
                                            .foregroundStyle(EditorTheme.dimText)
                                    }
                                }
                                .frame(width: cell, height: (cell * 9 / 16).rounded())
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(
                                            model.recipe.filter == filter
                                                ? EditorTheme.accent
                                                : EditorTheme.trackBorder,
                                            lineWidth: model.recipe.filter == filter ? 1.5 : 0.5
                                        )
                                }
                            Text(filter.displayName)
                                .font(.system(size: 9.5))
                                .foregroundStyle(
                                    model.recipe.filter == filter ? .white : EditorTheme.secondaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: cell)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.recipe.filter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, VideoStudioMetrics.mediaPoolCellSpacing)
            .padding(.vertical, 8)
        }
        .task(id: model.clipIndexUnderPlayhead) {
            lookThumbnails.refresh(
                for: model,
                photoLibrary: photoLibrary,
                cell: VideoStudioMetrics.mediaPoolCellWidth(columnWidth: width)
            )
        }
        .onDisappear { lookThumbnails.cancel() }
    }

    /// The imported-music library. Bundled tracks are gone (the catalogue is
    /// empty by design — see the music licensing note in spec §7.9), so this
    /// is what the user brought in from Files, plus the way to bring more.
    @ViewBuilder
    private var musicContent: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                actionRow(
                    systemImage: "square.and.arrow.down",
                    title: String(localized: "Import from Files…", comment: "Video Studio media pool: brings an audio file in from the Files app"),
                    action: onImportMusic
                )
                ForEach(importedMusic.tracks) { track in
                    Button {
                        model.addMusicTrack(source: .imported(url: track.url, displayName: track.displayName))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 13))
                                .foregroundStyle(EditorTheme.accent)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(EditorTheme.control)
                                )
                            Text(track.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Adds this to the music track", comment: "Video Studio media pool: what tapping a music row does"))
                }
                if importedMusic.tracks.isEmpty {
                    Text("Music you import is kept here for next time.", comment: "Video Studio media pool: empty state for the music tab")
                        .font(.system(size: 11))
                        .foregroundStyle(EditorTheme.dimText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    /// A font's own face at list size, the way the editor's font picker
    /// draws it.
    private static func preview(for choice: OverlayFontChoice) -> Font {
        guard !choice.postScriptName.isEmpty,
              let font = UIFont(name: choice.postScriptName, size: 15)
        else { return .system(size: 15) }
        return Font(font)
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
                    // The pool holds the most recent `capacity` items; this is
                    // the only way to anything older, and the only route to
                    // the system picker now that the rail's Add cell is gone.
                    actionRow(
                        systemImage: tab == .stickers ? "photo.badge.plus" : "rectangle.stack.badge.plus",
                        title: tab == .stickers
                            ? String(localized: "Choose a Sticker…", comment: "Video Studio media pool: opens the picker for a sticker image")
                            : String(localized: "Browse All Photos…", comment: "Video Studio media pool: opens the system picker for anything older than the pool holds"),
                        action: tab == .stickers ? onChooseSticker : onBrowseAll
                    )
                    switch presentation {
                    case .grid: gridBody
                    case .list: listBody
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }

    private var gridBody: some View {
        let cell = VideoStudioMetrics.mediaPoolCellWidth(columnWidth: width)
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(cell), spacing: VideoStudioMetrics.mediaPoolCellSpacing),
                count: VideoStudioMetrics.mediaPoolColumnCount(columnWidth: width)
            ),
            spacing: VideoStudioMetrics.mediaPoolCellSpacing
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
        .padding(.horizontal, VideoStudioMetrics.mediaPoolCellSpacing)
        .padding(.vertical, 8)
    }

    private var listBody: some View {
        LazyVStack(spacing: 2) {
            ForEach(assets, id: \.localIdentifier) { asset in
                VideoMediaPoolRow(
                    asset: asset,
                    photoLibrary: photoLibrary,
                    onAdd: { append(asset) }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: Actions

    /// What a tap inserts, which is what the tab means.
    private func append(_ asset: PHAsset) {
        switch tab {
        case .media:
            model.insertMedia([
                VideoMediaPick(
                    assetID: asset.localIdentifier,
                    kind: asset.mediaType == .video ? .video : .photo
                )
            ])
        case .stickers:
            onAddSticker(asset)
        case .text, .music, .effects:
            // These tabs do not list the photo library, so no asset can
            // arrive from them.
            break
        }
    }

    private func reload() {
        guard tab.isLibrary else { return }
        guard photoLibrary.authorizationState.canReadLibrary else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        // A sticker is drawn over the frame, so a clip cannot be one.
        options.predicate = tab == .stickers ? Source.photos.predicate : source.predicate
        options.sortDescriptors = order.sortDescriptors
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
        case media, stickers, text, music, effects
        var id: String { rawValue }

        /// Whether this tab lists the photo library.
        var isLibrary: Bool { self == .media || self == .stickers }

        var systemImage: String {
            switch self {
            case .media: "photo.stack"
            case .stickers: "photo.badge.plus"
            case .text: "textformat"
            case .music: "music.note"
            case .effects: "camera.filters"
            }
        }

        var title: String {
            switch self {
            case .media: String(localized: "Media", comment: "Video Studio media pool tab: photos and videos to add as clips")
            case .stickers: String(localized: "Stickers", comment: "Video Studio media pool tab: photos to add as an overlay")
            case .text: String(localized: "Text", comment: "Video Studio media pool tab: captions to add over the frame")
            case .music: String(localized: "Music", comment: "Video Studio media pool tab: audio to add as a music bed")
            case .effects: String(localized: "Effects", comment: "Video Studio media pool tab: looks to apply to the project")
            }
        }

        var binTitle: String {
            switch self {
            case .media: String(localized: "All Media", comment: "Video Studio media pool bin label")
            case .stickers: String(localized: "Photos", comment: "Video Studio media pool bin label for the sticker tab")
            case .text: String(localized: "Recent Fonts", comment: "Video Studio media pool bin label for the text tab")
            case .music: String(localized: "Imported", comment: "Video Studio media pool bin label for the music tab")
            case .effects: String(localized: "Looks", comment: "Video Studio media pool bin label for the effects tab")
            }
        }
    }

    enum Source: String, CaseIterable, Identifiable {
        case all, videos, photos, favorites
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All Media", comment: "Video Studio media pool filter: everything in the library")
            case .videos: String(localized: "Videos", comment: "Video Studio media pool filter: video clips only")
            case .photos: String(localized: "Photos", comment: "Video Studio media pool filter: still photos only")
            case .favorites: String(localized: "Favorites", comment: "Video Studio media pool filter: items favorited in Photos")
            }
        }

        var predicate: NSPredicate {
            switch self {
            case .all:
                PhotoLibraryService.browsableMediaPredicate
            case .videos:
                NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            case .photos:
                NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            case .favorites:
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    PhotoLibraryService.browsableMediaPredicate,
                    NSPredicate(format: "favorite = YES"),
                ])
            }
        }
    }

    enum Order: String, CaseIterable, Identifiable {
        case newest, oldest, longest
        var id: String { rawValue }

        var title: String {
            switch self {
            case .newest: String(localized: "Newest First", comment: "Video Studio media pool sort order")
            case .oldest: String(localized: "Oldest First", comment: "Video Studio media pool sort order")
            case .longest: String(localized: "Longest First", comment: "Video Studio media pool sort order: longest video duration first")
            }
        }

        var sortDescriptors: [NSSortDescriptor] {
            switch self {
            case .newest: [NSSortDescriptor(key: "creationDate", ascending: false)]
            case .oldest: [NSSortDescriptor(key: "creationDate", ascending: true)]
            // A still has a zero duration, so this sorts clips to the top and
            // leaves the photos in date order underneath them.
            case .longest: [
                NSSortDescriptor(key: "duration", ascending: false),
                NSSortDescriptor(key: "creationDate", ascending: false),
            ]
            }
        }
    }

    enum Presentation: String, CaseIterable, Identifiable {
        case grid, list
        var id: String { rawValue }
        var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
        var title: String {
            switch self {
            case .grid: String(localized: "Grid", comment: "Video Studio media pool: thumbnail grid layout")
            case .list: String(localized: "List", comment: "Video Studio media pool: one row per item layout")
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

/// The list presentation's row: a 16:9 chip, the name, and what it is.
private struct VideoMediaPoolRow: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService
    let onAdd: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(EditorTheme.control)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .frame(width: 48, height: 27)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(VideoMediaPoolFormat.name(for: asset))
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(VideoMediaPoolFormat.subtitle(for: asset))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(EditorTheme.dimText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VideoMediaPoolFormat.accessibilityLabel(for: asset))
        .accessibilityHint(Text("Adds this to the end of the video track", comment: "Video Studio media pool: what tapping an item does"))
        .onDrag { PhotoDragItem.provider(for: asset) }
        .onAppear { load() }
    }

    private func load() {
        guard image == nil else { return }
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 48 * displayScale, height: 27 * displayScale),
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
