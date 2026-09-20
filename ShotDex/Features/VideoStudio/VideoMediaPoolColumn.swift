import Photos
import SwiftUI

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
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// Closes the column. The same control that opened it in the top band.
    let onClose: () -> Void

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
            toolRow
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
    }

    // MARK: Bands

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EditorTheme.accent)
            Text("Media", comment: "Video Studio: title of the library column beside the stage")
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
            Text(source.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text(countText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(EditorTheme.dimText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(EditorTheme.stickyHeader)
    }

    private var countText: String {
        assets.count >= Self.capacity
            ? String(localized: "\(Self.capacity)+", comment: "Video Studio media pool: the column is showing its first N items and the library holds more")
            : "\(assets.count)"
    }

    @ViewBuilder
    private var content: some View {
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
                switch presentation {
                case .grid: gridBody
                case .list: listBody
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

    private func append(_ asset: PHAsset) {
        model.appendMedia([
            VideoMediaPick(
                assetID: asset.localIdentifier,
                kind: asset.mediaType == .video ? .video : .photo
            )
        ])
    }

    private func reload() {
        guard photoLibrary.authorizationState.canReadLibrary else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.predicate = source.predicate
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
