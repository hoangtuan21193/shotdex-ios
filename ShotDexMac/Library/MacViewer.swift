import Photos
import SwiftUI

/// How the viewer sizes the photo (toolbar Fit ▾, View › Zoom).
enum MacViewerZoom: String, CaseIterable, Identifiable {
    case fit, actual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fit: String(localized: "Fit", comment: "Mac viewer zoom: the whole photo in the window")
        case .actual: String(localized: "Actual Size", comment: "Mac viewer zoom: one image pixel per screen pixel")
        }
    }
}

/// One photo in the library window (board `MAC_Viewer`, FS-18.02 §6): the
/// picture on the window's ground, the filmstrip under it, the inspector
/// beside it. The grid stays behind it, so closing returns to where it was.
struct MacViewerView: View {
    /// The open photo; nil closes the viewer.
    @Binding var photoId: String?
    /// The place's photos in the grid's order, and each one's place in it.
    let ids: [String]
    let positions: [String: Int]
    let zoom: MacViewerZoom
    let menu: MacPhotoMenu?
    /// The open photo's stars, flag and heart, drawn on the picture's corner.
    var marks: LibraryTableQueries.Details? = nil
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?
    /// The grid's cached asset for a filmstrip tile (no fetch on the main actor).
    var cachedAsset: (String) -> PHAsset? = { _ in nil }
    /// Z: Fit ↔ 100% (01b §3, every viewing surface).
    var toggleZoom: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let photoId {
                // Not rebuilt per photo: the last picture stays until the next one is in.
                MacViewerPhoto(id: photoId, zoom: zoom, picture: picture, asset: asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A mark key shows where the eyes are, inspector open or not.
                    .overlay(alignment: .bottomLeading) { MacViewerMarks(marks: marks).padding(12) }
                    // A click on the photo takes the keys back from a field in the inspector.
                    .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            }
            Divider()
            MacFilmstrip(ids: ids, index: photoId.flatMap { positions[$0] }, current: $photoId, picture: picture, asset: cachedAsset)
        }
        .background(MacTheme.content)
        // The keys while the viewer has the keyboard: ← → move, Esc closes,
        // the mark keys mark this photo (01b §3).
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        // A filmstrip click must not leave the keys with nobody.
        .onChange(of: photoId) { isFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .macViewerTakeKeys)) { _ in isFocused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            step(press.key == .leftArrow ? -1 : 1, beeps: press.phase == .down)
            return .handled
        }
        .onKeyPress(.escape) { photoId = nil; return .handled }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isEmpty, let key = press.characters.first else { return .ignored }
            if key == "z" { toggleZoom(); return .handled }
            guard let id = photoId, let menu else { return .ignored }
            if key == "." { menu.toggleFavorite([id]); return .handled }
            guard let action = MarkKeyCommand.action(for: key) else { return .ignored }
            menu.apply(action, to: [id])
            return .handled
        }
    }

    /// The next or previous photo in the grid's order; the ends stay put.
    private func step(_ delta: Int, beeps: Bool) {
        guard let id = photoId, let index = positions[id] else { return }
        let next = index + delta
        // One beep at the end, not one per key repeat.
        guard ids.indices.contains(next) else { if beeps { NSSound.beep() }; return }
        photoId = ids[next]
    }
}

/// The picture: the whole of it (Fit), or one image pixel per screen pixel
/// in a scroll view (Actual Size). Read off the main actor at the size it
/// is drawn; a better one replaces the first as it comes.
struct MacViewerPhoto: View {
    let id: String
    let zoom: MacViewerZoom
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?
    /// Actual Size at this percentage (full screen's steps); nil is 100%.
    var percent: Int? = nil
    /// The window viewer's margins around a fitted photo; none in full screen.
    var insets = true
    /// The part on screen while zoomed, in the photo's unit square (the Navigator).
    var onViewport: ((CGRect) -> Void)? = nil

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failed = false
    @State private var requestId: PHImageRequestID?
    @State private var lastSize: CGSize = .zero
    /// The photo the running request is for: a late answer for another is dropped.
    @State private var loadingFor: String?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    switch zoom {
                    case .fit:
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, insets ? 42 : 0)
                            .padding(.vertical, insets ? 28 : 0)
                    case .actual:
                        ScrollView([.horizontal, .vertical]) {
                            Image(decorative: image, scale: displayScale * 100 / CGFloat(percent ?? 100))
                                .interpolation(.high)
                        }
                        .defaultScrollAnchor(.center)
                        // Full screen has its Navigator: no scroller tracks over the photo.
                        .scrollIndicators(insets ? .automatic : .never)
                        .onScrollGeometryChange(for: CGRect.self) { geometry in
                            let size = geometry.contentSize
                            guard size.width > 0, size.height > 0 else { return .zero }
                            let visible = geometry.visibleRect
                            return CGRect(x: max(0, visible.minX / size.width), y: max(0, visible.minY / size.height),
                                          width: min(1, visible.width / size.width), height: min(1, visible.height / size.height))
                        } action: { _, rect in onViewport?(rect) }
                        // Each photo starts centred, not where the last one was scrolled.
                        .id(id)
                    }
                } else if failed {
                    ContentUnavailableView(String(localized: "Can’t Show This Photo", comment: "Mac viewer: the picture could not be read"),
                                           systemImage: "photo")
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: "\(id)-\(zoom.rawValue)-\(Int(proxy.size.width))x\(Int(proxy.size.height))") {
                await withTaskCancellationHandler {
                    await load(fitting: proxy.size)
                } onCancel: {
                    Task { @MainActor in cancelRequest() }
                }
            }
            // A photo left behind stops loading: no full decode or iCloud download for nothing.
            .onDisappear { cancelRequest() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Photo", comment: "Mac viewer: VoiceOver name of the picture"))
        .accessibilityAddTraits(.isImage)
    }

    private func load(fitting size: CGSize) async {
        // Settle a resize before asking for a new rendition.
        failed = false
        // Full size: never two 48 MP bitmaps at once — the last one goes first.
        if zoom == .actual, loadingFor != id { image = nil }
        loadingFor = id
        // A resize settles before a new rendition is asked for; a new photo goes at once.
        if size != lastSize {
            let isFirst = lastSize == .zero
            lastSize = size
            if !isFirst { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled else { return }
        }
        if let picture {
            image = picture(id)
            return
        }
        let pixels = zoom == .actual
            ? PHImageManagerMaximumSize
            : CGSize(width: max(size.width, 1) * displayScale, height: max(size.height, 1) * displayScale)
        let wanted = id
        // PhotoKit item: the rendition at the drawn size; the network is asked when it is only in iCloud.
        if let found = await Task.detached(priority: .userInitiated, operation: { PhotoLibraryService.fetchAssets(ids: [wanted]).first }).value {
            guard !Task.isCancelled else { return }
            cancelRequest()
            requestId = dependencies.photoLibrary.requestThumbnail(for: found, targetSize: pixels, contentMode: .aspectFit, allowNetwork: true) { result in
                guard loadingFor == wanted else { return }
                // Nothing came (no network slot, an error): say so rather than spin.
                guard let cg = result?.cgImage else { failed = image == nil; return }
                image = cg
            }
            return
        }
        // A folder or server photo: its file, read and scaled off the main actor.
        let info = try? await PhotoInfoQueries(database: dependencies.database).info(photoId: wanted)
        guard let url = info?.filePath.map({ URL(fileURLWithPath: $0) }) else { failed = image == nil; return }
        let maxPixel = zoom == .actual ? 0 : Int(max(pixels.width, pixels.height))
        let read = await Task.detached(priority: .userInitiated) { MacViewerPhoto.read(url, maxPixel: maxPixel) }.value
        guard !Task.isCancelled else { return }
        if let read { image = read } else { failed = image == nil }
    }

    private func cancelRequest() {
        if let requestId { dependencies.photoLibrary.cancelThumbnailRequest(requestId) }
        requestId = nil
    }

    /// The file's picture, scaled to `maxPixel` (0: full size), rotated upright.
    nonisolated static func read(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        if maxPixel > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// The strip of neighbours under the photo (board): 64pt tiles, the open
/// one ringed in amber; a click opens it. Only the photos near the open one
/// are built — a 55k library has no 55k-wide strip.
struct MacFilmstrip: View {
    let ids: [String]
    /// The open photo's place in `ids`, looked up by the caller's map.
    let index: Int?
    @Binding var current: String?
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?

    static let window = 40

    var body: some View {
        // One search for the open photo; each tile's place is its offset from it.
        let index = self.index
        let range: Range<Int> = index.map { max(0, $0 - Self.window)..<min(ids.count, $0 + Self.window + 1) } ?? 0..<0
        let shown = Array(range).map { (position: $0, id: ids[$0]) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(shown, id: \.id) { tile in
                        let id = tile.id
                        Button { current = id } label: {
                            MacFilmstripTile(id: id, picture: picture, asset: asset, isCurrent: id == current)
                        }
                        .buttonStyle(.plain)
                        .id(id)
                        .accessibilityLabel(String(localized: "Photo \(tile.position + 1) of \(ids.count)",
                                                   comment: "Mac viewer filmstrip: a tile's position"))
                        .accessibilityAddTraits(id == current ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 88)
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: current) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Filmstrip", comment: "Mac viewer: the strip of photos under the open one"))
    }
}

struct MacFilmstripTile: View {
    let id: String
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?
    let isCurrent: Bool
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?

    var body: some View {
        // 64 at a 68 pitch; the open one ringed inside its edge, 2pt amber then 2pt ground (board).
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MacTheme.fill2)
            .overlay { if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: 64, height: 64)
            .overlay {
                if isCurrent {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(MacTheme.accent, lineWidth: 2)
                        RoundedRectangle(cornerRadius: 2, style: .continuous).inset(by: 2).strokeBorder(MacTheme.content, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .task(id: id) {
                if let picture { image = picture(id); return }
                guard let found = asset(id) else { return }
                let request = dependencies.photoLibrary.requestThumbnail(for: found, targetSize: CGSize(width: 128, height: 128), allowNetwork: false) { result in
                    if let cg = result?.cgImage { image = cg }
                }
                await withTaskCancellationHandler {
                    try? await Task.sleep(for: .seconds(30))
                } onCancel: {
                    Task { @MainActor in dependencies.photoLibrary.cancelThumbnailRequest(request) }
                }
            }
    }
}

/// The viewer's inspector (board `MAC_Viewer`): Rating and Flag, Histogram,
/// Caption and Keywords, Camera and Lens, Edits, Location and File.
struct MacViewerInspector: View {
    let photoId: String
    let marks: LibraryTableQueries.Details?
    let menu: MacPhotoMenu?
    var picture: ((String) -> CGImage?)? = nil
    @Environment(MacDependencies.self) private var dependencies
    @State private var info: PhotoInfoQueries.Info?
    @State private var loadedId: String?
    /// Bumped after a caption or keyword write: the facts are read again.
    @State private var reloads = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(String(localized: "Rating and Flag", comment: "Mac viewer inspector section")) { ratingAndFlag }
                section(String(localized: "Histogram", comment: "Mac viewer inspector section")) {
                    MacViewerHistogram(photoId: photoId, picture: picture)
                }
                // The last photo's facts stay until the new ones come (no spinner per step).
                if let info {
                    section(String(localized: "Caption and Keywords", comment: "Mac viewer inspector section")) {
                        MacViewerCaptionKeywords(photoId: photoId, info: info, isCurrent: loadedId == photoId) {
                            reloads += 1
                            menu?.marksChanged([photoId])
                        }
                    }
                    section(String(localized: "Camera and Lens", comment: "Mac viewer inspector section")) { camera(info) }
                    MacViewerEdits(photoId: photoId, reloads: reloads + (menu?.marksGeneration ?? 0), hasFileCopy: loadedId == photoId && info.hasFileCopy)
                    if let place = MacInfoText.place(info) {
                        section(String(localized: "Location", comment: "Mac viewer inspector section"), accessory: {
                            if let coordinate = MacInfoText.coordinate(info) {
                                Button { MacViewerLocation.showOnMap(coordinate, name: place.name) } label: {
                                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MacTheme.accent)
                                        .frame(width: 22, height: 22)
                                        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Show on Map", comment: "Mac viewer: open Maps at the photo's place"))
                                .help(String(localized: "Show on Map", comment: "Mac viewer: open Maps at the photo's place"))
                            }
                        }) {
                            if let coordinate = MacInfoText.coordinate(info) {
                                MacViewerLocation(coordinate: coordinate, place: place)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = place.name { Text(name).font(.system(size: 13)) }
                                }
                            }
                        }
                    }
                    section(String(localized: "File", comment: "Mac viewer inspector section")) { file(info) }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(MacTheme.content)
        // Again when a caption or keyword changes here or in Get Info.
        .task(id: "\(photoId)-\(reloads)-\(menu?.marksGeneration ?? 0)") {
            // Off the main actor; the last photo's facts stay until the new ones come.
            guard let read = try? await PhotoInfoQueries(database: dependencies.database).info(photoId: photoId) else {
                // A failed read shows nothing rather than the last photo's facts.
                if !Task.isCancelled { info = nil }
                return
            }
            guard !Task.isCancelled else { return }
            info = read
            loadedId = photoId
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, accessory: { EmptyView() }, content: content)
    }

    private func section<Accessory: View, Content: View>(_ title: String, @ViewBuilder accessory: () -> Accessory,
                                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                accessory()
            }
            content()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var ratingAndFlag: some View {
        let rating = marks?.rating ?? 0
        let flag = marks?.flag
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        menu?.apply(.rate(rating == star ? 0 : star), to: [photoId])
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .frame(width: 20, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MarkCopy.starsAccessibility(star))
                    .accessibilityAddTraits(star <= rating ? [.isSelected] : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MarkCopy.rating)
            Spacer(minLength: 4)
            MacFittedSegments(title: String(localized: "Flag", comment: "Mac viewer: the flag control"),
                              options: [(String(localized: "None", comment: "Mac viewer flag: no flag"), MacViewerFlag.none),
                                        (String(localized: "Pick", comment: "Mac viewer flag: the verb, as the board"), .pick),
                                        (String(localized: "Reject", comment: "Mac viewer flag: the verb, as the board"), .reject)],
                              selection: MacViewerFlag(flag)) { choice in
                menu?.apply(.flag(choice.flag), to: [photoId])
            }
        }
    }

    private func camera(_ info: PhotoInfoQueries.Info) -> some View {
        let metadata = info.metadata
        return VStack(alignment: .leading, spacing: 8) {
            row(String(localized: "Camera", comment: "Mac viewer inspector row"), metadata?.normalizedCameraModel ?? metadata?.cameraModel)
            row(String(localized: "Lens", comment: "Mac viewer inspector row"), metadata?.normalizedLensModel ?? metadata?.lensModel)
            if metadata?.iso == nil, metadata?.focalLength == nil, metadata?.aperture == nil, metadata?.shutterSpeedDisplay == nil {
                Text("No camera data", comment: "Mac viewer inspector: the photo has no exposure facts")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
            HStack(spacing: 4) {
                tile(metadata?.iso.map { "\($0)" }, String(localized: "ISO", comment: "Mac viewer exposure tile"))
                tile(metadata?.focalLength.map { "\(Int($0.rounded())) mm" }, String(localized: "Focal", comment: "Mac viewer exposure tile"))
                tile(metadata?.aperture.map { "f/" + $0.formatted(.number.precision(.fractionLength(0...1))) },
                     String(localized: "Aperture", comment: "Mac viewer exposure tile"))
                tile(metadata?.shutterSpeedDisplay.map { "\($0) s" }, String(localized: "Shutter", comment: "Mac viewer exposure tile"))
            }
            }
        }
    }

    private func tile(_ value: String?, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text(value ?? "—").font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func file(_ info: PhotoInfoQueries.Info) -> some View {
        let metadata = info.metadata
        VStack(alignment: .leading, spacing: 6) {
            row(String(localized: "Source", comment: "Mac viewer inspector row"), marks?.sourceName)
            if let path = info.filePath {
                Text(path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            row(String(localized: "Size", comment: "Mac viewer inspector row"),
                metadata?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
            row(String(localized: "Dimensions", comment: "Mac viewer inspector row"), dimensions(metadata))
            row(String(localized: "Format", comment: "Mac viewer inspector row"),
                (info.fileName ?? metadata?.originalFilename).map { ($0 as NSString).pathExtension.uppercased() }.flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    private func dimensions(_ metadata: PhotoMetadata?) -> String? {
        guard let width = metadata?.width, let height = metadata?.height, width > 0, height > 0 else { return nil }
        let megapixels = (Double(width * height) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
        return "\(width) × \(height) · \(megapixels) MP"
    }

    @ViewBuilder
    private func row(_ name: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                Text(value).font(.system(size: 13)).lineLimit(2).textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The flag control's three choices, Hashable for the segments.
enum MacViewerFlag: Hashable {
    case none, pick, reject
    init(_ flag: PhotoFlag?) {
        switch flag {
        case .pick?: self = .pick
        case .reject?: self = .reject
        default: self = .none
        }
    }
    var flag: PhotoFlag? {
        switch self {
        case .none: nil
        case .pick: .pick
        case .reject: .reject
        }
    }
}

/// Stars, flag and heart on the picture's corner (a dark capsule that reads
/// on any photo); nothing while the photo has none.
struct MacViewerMarks: View {
    let marks: LibraryTableQueries.Details?

    var body: some View {
        let rating = marks?.rating ?? 0
        let flag = marks?.flag
        let isFavorite = marks?.isFavorite ?? false
        if rating > 0 || flag != nil || isFavorite {
            HStack(spacing: 6) {
                if isFavorite { Image(systemName: "heart.fill") }
                if rating > 0 { Text(String(repeating: "★", count: rating)) }
                if let flag {
                    Image(systemName: flag == .pick ? "flag.fill" : "xmark")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MacTileMarks.spoken(marks) ?? "")
        }
    }
}
