import Photos
import SwiftUI

/// The shared frame picker (FS-06.06 §8, FS-02.05 §4; board `PH_BurstFrames`),
/// tier D: one run of frames of one moment — a PhotoKit burst, a Burst
/// group, a focus stack. The big frame takes every point of height the
/// chrome leaves; zoom and pan carry over to the next frame, so eyes are
/// compared at the same spot; a 56pt filmstrip marks weak frames with a red
/// dot. The keep button sits at the frame's bottom right, Done and the red
/// "Keep 3, remove 21" in the thumb zone; swipe down closes — there is no X.
struct BurstFramesScreen: View {
    let request: BurstFramesRequest
    /// Told what was kept after a delete, so the caller can stand on it.
    var onDeleted: (([String]) -> Void)?
    /// Done: the frames kept now. A Duplicates group turns them into marks.
    var onDone: (([String]) -> Void)?
    /// A Duplicates group's own delete (inheritance, banner); `nil` for a
    /// burst opened from the viewer.
    var groupDelete: (([String]) async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.appAccent) private var accent

    @State private var model: BurstFramesModel?
    @State private var synchronizer = CompareScrollSynchronizer()
    /// Which face Zoom to face went to last; the next tap moves on (§8).
    @State private var faceTaps = 0
    /// iPad: 2–6 frames side by side, zoomed together (Compare's Survey).
    @State private var isSurvey = false

    /// Survey is an iPad mode: a phone has no room for two frames worth judging.
    private var offersSurvey: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static let surveyCount = 6

    static let filmstripCell: CGFloat = 56

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model {
                content(model)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            guard model == nil else { return }
            let photoLibrary = photoLibrary
            let made = BurstFramesModel(
                request: request,
                library: dependencies.bursts,
                isLimited: photoLibrary.authorizationState == .limited,
                banner: dependencies.banner,
                groupDelete: groupDelete,
                deleteAssets: { ids in
                    let assets = PhotoLibraryService.fetchAssets(ids: ids)
                    guard !assets.isEmpty else { return 0 }
                    try await photoLibrary.deleteAssetsCheckingServer(assets)
                    return assets.count
                }
            )
            model = made
            await made.load()
        }
    }

    @ViewBuilder
    private func content(_ model: BurstFramesModel) -> some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height && proxy.size.width >= 700
            VStack(spacing: 0) {
                topBar(model)
                    // The Duo's cover keeps no status bar above the app: start
                    // the bar clear of the display's ~37pt corner curve.
                    .padding(.top, max(0, Self.cornerClearance - proxy.safeAreaInsets.top))
                if let note = model.limitedNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, CullLayout.edgeInset)
                        .padding(.bottom, AppTheme.Spacing.sm)
                }
                switch model.phase {
                case .loading:
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                case .empty:
                    Spacer()
                    Text("This burst has no other frames ShotDex can see.", comment: "Burst frame picker: fewer than two frames visible")
                        .font(.subheadline)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "Close", comment: "Frame picker: leave the empty state"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.Spacing.xl)
                            .frame(height: 48)
                            .editorGlass(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                case .ready:
                    if isSurvey {
                        surveyGrid(model)
                        filmstrip(model, vertical: false)
                    } else if isWide {
                        // Duo inner (951×669) and landscape iPad: the strip
                        // runs down the right edge so the frame keeps the
                        // whole height (§8, board `DI_BurstFrames`).
                        HStack(spacing: 0) {
                            bigFrame(model)
                            filmstrip(model, vertical: true)
                        }
                    } else {
                        bigFrame(model)
                        filmstrip(model, vertical: false)
                    }
                    bottomBar(model)
                }
            }
        }
        .background { keyButtons(model) }
    }

    // MARK: Top bar

    /// Keep Only Suggested (a burst) · title · Zoom to face.
    private func topBar(_ model: BurstFramesModel) -> some View {
        let currentId = model.selection.current?.id
        return HStack(spacing: AppTheme.Spacing.md) {
            if model.selection.hasSuggestions {
                glassButton(String(localized: "Keep Only Suggested", comment: "Burst frame picker: keep exactly the frames Photos suggested")) {
                    model.keepOnlySuggested()
                }
            }
            Text(model.selection.count > 0 ? (request.title.map { "\($0) · \(model.selection.currentIndex + 1)/\(model.selection.count)" } ?? model.selection.title) : "")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: model.selection.hasSuggestions ? .leading : .center)
            if offersSurvey {
                Picker(String(localized: "View", comment: "Frame picker: one frame or several"), selection: $isSurvey) {
                    Text(String(localized: "Single", comment: "Frame picker: one big frame")).tag(false)
                    Text(String(localized: "Survey", comment: "Frame picker: several frames side by side")).tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .colorScheme(.dark)
            }
            if let currentId, let face = model.faceRect(for: currentId) {
                glassButton(String(localized: "Zoom to face", comment: "Frame picker: zoom the big frame onto the largest face")) {
                    zoomToFace(face, model: model)
                }
            }
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .frame(height: CullLayout.topBarHeight)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(height: CullLayout.control)
                .editorGlass(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// The face at about 100%: one pixel of the photo per pixel of screen.
    private func zoomToFace(_ face: CGRect, model: BurstFramesModel) {
        guard let id = model.selection.current?.id, let asset = model.asset(for: id) else { return }
        let fitWidth = max(1, UIScreen.main.bounds.width) * ActiveDisplay.scale
        let scale = max(2, min(5, CGFloat(asset.pixelWidth) / fitWidth))
        synchronizer.zoom(frameAt: 0, toNormalized: face, scale: scale)
        faceTaps += 1
    }

    // MARK: Big frame

    private func bigFrame(_ model: BurstFramesModel) -> some View {
        let selection = model.selection
        let frame = selection.current
        let isKept = frame.map { selection.isKept($0.id) } ?? false
        return ZStack {
            if let frame {
                BurstBigFrame(
                    asset: model.asset(for: frame.id),
                    photoLibrary: photoLibrary,
                    synchronizer: synchronizer,
                    onSwipe: { swipe in
                        switch swipe {
                        case .left: model.next()
                        case .right: model.previous()
                        case .down: close(model)
                        case .up: break
                        }
                    }
                )
                // A new scroll view per frame: the synchronizer replays the
                // last zoom and pan onto it, so the next frame opens in step.
                .id(frame.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let frame {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if frame.isSuggested { chip(BurstSelection.suggestedTitle, fill: accent, text: .black) }
                    if frame.isPickedInPhotos { chip(BurstSelection.pickedInPhotosTitle, fill: .white.opacity(0.22), text: .white) }
                    ForEach(model.chips(for: frame.id), id: \.self) { title in
                        chip(title, fill: .black.opacity(0.55), text: .white)
                    }
                }
                .padding(CullLayout.edgeInset)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                model.toggleKeepCurrent()
            } label: {
                keepBadge(isKept: isKept, size: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(CullLayout.edgeInset)
            .accessibilityLabel(isKept
                ? String(localized: "Don't keep", comment: "Frame picker: take the keep back")
                : String(localized: "Keep", comment: "Frame picker: keep this frame"))
        }
        .contextMenu {
            if let frame {
                Button {
                    model.keepOnly(frame.id)
                } label: {
                    Label(Self.keepOnlyTitle, systemImage: "checkmark.circle")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selection.accessibilityLabel(at: selection.currentIndex))
        .accessibilityAction(named: Text(Self.keepOnlyTitle)) {
            if let frame { model.keepOnly(frame.id) }
        }
        .sensoryFeedback(.selection, trigger: selection.keptIds)
    }

    static let cornerClearance: CGFloat = 24

    static var keepOnlyTitle: String {
        String(localized: "Keep just this one", comment: "Frame picker: keep this frame and no other")
    }

    private func chip(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(text)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(height: 26)
            .background(Capsule().fill(fill))
    }

    /// Kept = accent disc + black tick (tier D's active); not kept = an
    /// empty ring, so the frame reads as something to tap.
    private func keepBadge(isKept: Bool, size: CGFloat) -> some View {
        ZStack {
            if isKept {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.black)
            } else {
                Circle().strokeBorder(.white, lineWidth: 2).background(Circle().fill(.black.opacity(0.2)))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    // MARK: Survey

    /// Up to six frames from the one in view, every pane on the same
    /// synchronizer: zoom one and they all zoom to the same spot (AC-F4).
    /// A tap makes a pane the current frame; each has its keep button.
    private func surveyGrid(_ model: BurstFramesModel) -> some View {
        let selection = model.selection
        let start = min(selection.currentIndex, max(0, selection.count - Self.surveyCount))
        let frames = Array(selection.frames.dropFirst(start).prefix(Self.surveyCount))
        let columns = frames.count <= 2 ? frames.count : (frames.count <= 4 ? 2 : 3)
        return GeometryReader { proxy in
            let rows = Int(ceil(Double(frames.count) / Double(max(columns, 1))))
            let cell = CGSize(width: (proxy.size.width - CGFloat(columns - 1) * 4) / CGFloat(max(columns, 1)),
                              height: (proxy.size.height - CGFloat(rows - 1) * 4) / CGFloat(max(rows, 1)))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: 4), count: max(columns, 1)), spacing: 4) {
                ForEach(Array(frames.enumerated()), id: \.element.id) { offset, frame in
                    let index = start + offset
                    let isKept = selection.isKept(frame.id)
                    BurstBigFrame(asset: model.asset(for: frame.id), photoLibrary: photoLibrary,
                                  synchronizer: synchronizer, paneIndex: offset, onSwipe: { _ in },
                                  onTap: { model.show(index) })
                        .frame(width: cell.width, height: cell.height)
                        .overlay {
                            if index == selection.currentIndex {
                                Rectangle().strokeBorder(accent, lineWidth: 2).allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                ForEach(model.chips(for: frame.id), id: \.self) { chip($0, fill: .black.opacity(0.55), text: .white) }
                            }
                            .padding(AppTheme.Spacing.sm)
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                model.show(index)
                                model.toggleKeepCurrent()
                            } label: {
                                keepBadge(isKept: isKept, size: 30).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(AppTheme.Spacing.sm)
                        }
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(selection.accessibilityLabel(at: index))
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    // MARK: Filmstrip

    private func filmstrip(_ model: BurstFramesModel, vertical: Bool) -> some View {
        let selection = model.selection
        let cell = Self.filmstripCell
        return ScrollViewReader { reader in
            ScrollView(vertical ? .vertical : .horizontal) {
                let cells = ForEach(Array(selection.frames.enumerated()), id: \.element.id) { index, frame in
                    Button {
                        model.show(index)
                    } label: {
                        CullThumbnail(asset: model.asset(for: frame.id), photoLibrary: photoLibrary, side: cell)
                            .frame(width: cell, height: cell)
                            .overlay(alignment: .bottomTrailing) {
                                if selection.isKept(frame.id) {
                                    keepBadge(isKept: true, size: 16).padding(2)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if frame.isSuggested {
                                    Circle().fill(accent).frame(width: 6, height: 6).padding(3)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                // A weak frame (Eyes closed, Soft) — not "will go".
                                if model.isWeak(frame.id) {
                                    Circle().fill(Color.red).frame(width: 6, height: 6).padding(3)
                                }
                            }
                            .overlay {
                                if index == selection.currentIndex {
                                    Rectangle().strokeBorder(accent, lineWidth: 2)
                                }
                            }
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    .id(frame.id)
                    .accessibilityLabel(selection.accessibilityLabel(at: index)
                        + (model.isWeak(frame.id) ? ", " + String(localized: "weak", comment: "VoiceOver: a frame the scores found weak") : ""))
                    .accessibilityAddTraits(index == selection.currentIndex ? [.isSelected, .isButton] : .isButton)
                }
                if vertical {
                    LazyVStack(spacing: 4) { cells }.padding(.vertical, AppTheme.Spacing.sm)
                } else {
                    LazyHStack(spacing: 4) { cells }.padding(.horizontal, CullLayout.edgeInset)
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: vertical ? 72 : nil, height: vertical ? nil : cell + AppTheme.Spacing.sm * 2)
            .onChange(of: selection.currentIndex) { _, _ in
                guard let id = selection.current?.id else { return }
                withAnimation(AppTheme.Motion.standard) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MarkCopy.filmstrip)
    }

    // MARK: Bottom

    /// Done · Keep 3, remove 21 — both in the thumb zone (A6).
    private func bottomBar(_ model: BurstFramesModel) -> some View {
        let selection = model.selection
        return VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    close(model)
                } label: {
                    Text(String(localized: "Done", comment: "Frame picker: close, keeping the picks as the group's marks"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .frame(height: 48)
                        .editorGlass(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                Button {
                    Task { await delete(model) }
                } label: {
                    Text(selection.deleteTitle)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(Color.red))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!selection.canDelete || model.isDeleting)
                .opacity(selection.canDelete ? 1 : 0.35)
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .frame(maxWidth: CullLayout.controlRowWidth + 120)
            Text(selection.deleteFootnote)
                .font(.caption)
                .foregroundStyle(EditorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private func close(_ model: BurstFramesModel) {
        onDone?(model.keptIds)
        dismiss()
    }

    private func delete(_ model: BurstFramesModel) async {
        if case .deleted(let kept) = await model.deleteUnkept() {
            onDeleted?(kept)
            dismiss()
        }
    }

    // MARK: Keys

    private func keyButtons(_ model: BurstFramesModel) -> some View {
        ZStack {
            Button(MarkCopy.nextPhoto) { model.next() }.keyboardShortcut(.rightArrow, modifiers: [])
            Button(MarkCopy.previousPhoto) { model.previous() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button(Self.keepOnlyTitle) { model.toggleKeepCurrent() }.keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// The big frame: zoomable, in step with the frames before it. The best
/// local rendition first, then the screen-sized one.
struct BurstBigFrame: View {
    let asset: PHAsset?
    let photoLibrary: PhotoLibraryService
    let synchronizer: CompareScrollSynchronizer
    var paneIndex = 0
    let onSwipe: (CullGesturePolicy.Swipe) -> Void
    var onTap: (() -> Void)?
    var onHoldChange: ((Bool) -> Void)?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                ZoomableImageView(image: image, sync: synchronizer, paneIndex: paneIndex, onHoldChange: onHoldChange, onSingleTap: onTap, onSwipe: onSwipe)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil, let asset else { return }
        let target = ActiveDisplay.pixelSize()
        _ = photoLibrary.requestBestLocalImage(for: asset, targetSize: target) { result in
            guard let result else { return }
            if image == nil || result.size.width * result.scale > (image?.size.width ?? 0) * (image?.scale ?? 1) {
                image = result
            }
        }
        _ = photoLibrary.requestDetailImage(for: asset, targetSize: target, allowNetwork: true, progress: { _ in }) { result, isDegraded in
            if let result, !isDegraded { image = result }
        }
    }
}
