import Photos
import SwiftUI

/// The culling pass (FS-01.12b), tier D on black, Lightroom-mobile shaped:
/// top bar (✕ · `37 / 240` · Undo), the photo, the 340pt row
/// `[Reject] [★★★★★] [Pick]`, and the filmstrip. Marks are written as they
/// are set; closing ends the pass and its undo.
struct CullScreen: View {
    @State var model: CullModel
    let photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    /// Delete N Rejected…: the system's deletion, its dialog the only
    /// confirmation (FS-01.12b §3).
    var deleteRejectedPhotos: (([String]) async -> Void)?

    private func deleteRejected() {
        let ids = model.rejectedIds
        guard !ids.isEmpty, let deleteRejectedPhotos else { return }
        Task { await deleteRejectedPhotos(ids) }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = CullLayout.forSize(proxy.size)
            VStack(spacing: 0) {
                topBar
                if layout.showsEXIFLine { exifLine }
                photo
                controlRow
                CullFilmstrip(model: model, photoLibrary: photoLibrary, layout: layout)
            }
            .overlay {
                if model.isSummaryPresented {
                    CullSummaryCard(
                        summary: model.summary,
                        onDeleteRejected: deleteRejectedPhotos == nil ? nil : deleteRejected,
                        onReviewUnflagged: { model.reviewUnflagged() },
                        onDone: { dismiss() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(EditorTheme.animation, value: model.isSummaryPresented)
            .onAppear {
                let scale = ActiveDisplay.scale
                model.targetSize = CGSize(width: proxy.size.width * scale, height: proxy.size.height * scale)
                model.loadCurrent()
            }
        }
        .background(EditorTheme.background.ignoresSafeArea())
        .background { keyButtons }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onDisappear { model.stop() }
    }

    // MARK: Keys

    /// `P X U 0–5 Z` and ←/→ on hidden buttons — the menu-less screen's
    /// keys still go through the same calls the buttons make.
    private var keyButtons: some View {
        ZStack {
            ForEach(CullKey.characterBindings, id: \.0) { key, action in
                Button(Self.keyTitle(action)) { Task { await model.handle(action) } }
                    .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            }
            Button(MarkCopy.previousPhoto) { Task { await model.handle(.previous) } }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(MarkCopy.nextPhoto) { Task { await model.handle(.next) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private static func keyTitle(_ key: CullKey) -> String {
        switch key {
        case .mark(let action): action.shortcutTitle
        case .zoom: MarkCopy.zoom
        case .previous: MarkCopy.previousPhoto
        case .next: MarkCopy.nextPhoto
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(model.session.counter)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                let summary = model.summary
                Text(MarkCopy.cullProgress(picks: summary.picks, rejected: summary.rejected))
                    .font(.system(size: 12))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            HStack {
                roundButton(systemImage: "xmark", glyph: 18, label: MarkCopy.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                roundButton(systemImage: "arrow.uturn.backward", glyph: 19, label: MarkCopy.undo) {
                    Task { await model.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.28)
            }
            .padding(.horizontal, CullLayout.edgeInset)
        }
        .frame(height: CullLayout.topBarHeight)
    }

    private var exifLine: some View {
        Text(exifText)
            .font(.system(size: 12))
            .foregroundStyle(EditorTheme.secondaryText)
            .lineLimit(1)
            .frame(height: CullLayout.exifLineHeight)
            .frame(maxWidth: .infinity)
    }

    private var exifText: String {
        guard let asset = model.currentAsset else { return "" }
        return asset.creationDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? ""
    }

    // MARK: Photo

    private var photo: some View {
        ZStack {
            if let image = model.image {
                ZoomableImageView(
                    image: image, onZoomChange: { model.zoomScale = $0 },
                    zoomToggleToken: model.zoomToggleToken
                )
                .id(model.currentId)
            } else {
                ProgressView().tint(EditorTheme.secondaryText)
            }
            if model.isCurrentVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white.opacity(0.9))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MarkCopy.cullPhoto(
            index: model.session.index + 1, total: model.session.ids.count,
            marks: model.currentMarks, isVideo: model.isCurrentVideo
        ))
    }

    // MARK: Control row

    private var controlRow: some View {
        let marks = model.currentMarks
        return HStack(spacing: CullLayout.controlGap) {
            flagButton(.reject, isOn: marks.flag == .reject)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        Task { await model.setRating(marks.rating == stars ? 0 : stars) }
                    } label: {
                        Image(systemName: stars <= marks.rating ? "star.fill" : "star")
                            .font(.system(size: CullLayout.starGlyph))
                            .foregroundStyle(stars <= marks.rating ? Color.white : Color.white.opacity(0.28))
                            .frame(width: CullLayout.control, height: CullLayout.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                    .accessibilityAddTraits(stars <= marks.rating ? .isSelected : [])
                }
            }
            flagButton(.pick, isOn: marks.flag == .pick)
        }
        .frame(width: CullLayout.controlRowWidth, height: CullLayout.controlRowHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MarkCopy.ratingAndFlag)
    }

    /// Pick on = accent disc + black glyph; Reject on = red disc + white
    /// glyph, the destructive "on" (DESIGN.md tier D). Tapping the flag the
    /// photo already has clears it.
    private func flagButton(_ flag: PhotoFlag, isOn: Bool) -> some View {
        Button {
            Task { await model.setFlag(isOn ? nil : flag) }
        } label: {
            Image(systemName: flag == .pick ? "flag.fill" : "xmark")
                .font(.system(size: flag == .pick ? 19 : 20, weight: .semibold))
                .foregroundStyle(isOn ? (flag == .pick ? Color.black : Color.white) : Color.white)
                .frame(width: CullLayout.control, height: CullLayout.control)
                .background {
                    if isOn {
                        Circle().fill(flag == .pick ? EditorTheme.accent : Color.red)
                    }
                }
                .editorGlass(Circle(), tint: isOn ? .clear : EditorTheme.glass)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flag == .pick ? MarkCopy.pick : MarkCopy.reject)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func roundButton(systemImage: String, glyph: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: CullLayout.control, height: CullLayout.control)
                .editorGlass(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The pass's strip: square cells, the current one ringed in white, each
/// with its flag and stars (FS-01.12b §5). Tapping a cell goes there.
struct CullFilmstrip: View {
    let model: CullModel
    let photoLibrary: PhotoLibraryService
    let layout: CullLayout

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(model.session.ids.enumerated()), id: \.offset) { index, id in
                        cell(id: id, index: index).id(index)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxHeight: .infinity)
            }
            .onAppear { proxy.scrollTo(model.session.index, anchor: .center) }
            .onChange(of: model.session.index) { _, new in
                withAnimation(EditorTheme.animation) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(height: layout.filmstripHeight)
        // Stops at the strip: below it is the home indicator's black, as on
        // the board, not a slab running to the screen's edge.
        .background(EditorTheme.panelSolid, ignoresSafeAreaEdges: [])
        .accessibilityLabel(MarkCopy.filmstrip)
    }

    private func cell(id: String, index: Int) -> some View {
        let marks = model.marks(for: id)
        let isCurrent = index == model.session.index
        return Button {
            model.show(index: index)
        } label: {
            CullThumbnail(asset: model.asset(for: id), photoLibrary: photoLibrary, side: layout.filmstripCell)
                .frame(width: layout.filmstripCell, height: layout.filmstripCell)
                .opacity(marks.flag == .reject ? 0.45 : 1)
                .overlay(alignment: .topLeading) { glyphs(marks) }
                .overlay {
                    if isCurrent { Rectangle().strokeBorder(.white, lineWidth: 2) }
                }
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MarkCopy.cullPhoto(index: index + 1, total: model.session.ids.count, marks: marks, isVideo: model.asset(for: id)?.mediaType == .video))
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private func glyphs(_ marks: PhotoMarkSummary) -> some View {
        if !marks.isEmpty {
            HStack(spacing: 2) {
                if let flag = marks.flag {
                    Image(systemName: flag == .pick ? "flag.fill" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                if marks.rating > 0 {
                    Text(MarkCopy.compactStars(marks.rating))
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 1.5)
            .padding(3)
        }
    }
}

/// One filmstrip cell's thumbnail.
struct CullThumbnail: View {
    let asset: PHAsset?
    let photoLibrary: PhotoLibraryService
    let side: CGFloat
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        Rectangle()
            .fill(EditorTheme.control)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear {
                if let request { photoLibrary.cancel(request) }
            }
    }

    private func load() {
        guard image == nil, let asset else { return }
        let scale = ActiveDisplay.scale
        // A plain request, not the grid's thumbnail ladder (which holds its
        // network pass back while others run — a strip cell stayed blank)
        // and not the detail path (whose 12-image cache the strip would
        // empty of the photo on screen).
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        request = photoLibrary.imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: side * scale, height: side * scale),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            Task { @MainActor in
                if let image { self.image = image }
            }
        }
    }
}

/// Builds the pass once its photos are fetched — a whole library's worth
/// for Cull From Here, so off the main actor.
struct CullHost: View {
    let request: CullRequest
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: CullModel?

    var body: some View {
        Group {
            if let model {
                CullScreen(model: model, photoLibrary: dependencies.photoLibrary)
            } else {
                EditorTheme.background.ignoresSafeArea()
            }
        }
        .appBannerHost(dependencies.banner, bottomInset: 140)
        .task {
            guard model == nil else { return }
            let ids = request.assetIds
            let assets = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.fetchAssets(ids: ids)
            }.value
            model = CullModel(
                request: request, marks: dependencies.photoMarks,
                loader: dependencies.photoLibrary, assets: assets
            )
        }
    }
}

extension View {
    /// Presents the culling pass for whatever sets `request` — the selection
    /// ⋯ through `AppNavigation`, the viewer's ⋯ through its own state.
    func cullPresenter(_ request: Binding<CullRequest?>) -> some View {
        fullScreenCover(item: request) { CullHost(request: $0) }
    }
}

/// `Cull N Photos` in a selection's ⋯, right after Combine Photos
/// (FS-01.12b §5). Reads the root's navigation itself so no screen has to
/// thread it through.
struct CullSelectionRow: View {
    let ids: [String]
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.cullRequest = CullRequest(assetIds: ids)
        } label: {
            Label(MarkCopy.cullPhotos(ids.count), systemImage: PhotoCommand.cull.systemImage)
        }
        .disabled(ids.isEmpty)
    }
}
