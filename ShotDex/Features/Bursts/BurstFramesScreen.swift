import Photos
import SwiftUI

/// The burst frame picker (FS-02.05 §4), tier D: one big frame and a strip
/// of every frame at the bottom, like Photos' own. A tap on the big frame
/// keeps it or takes the keep back; the red button deletes the frames **not**
/// kept, through the system's dialog.
struct BurstFramesScreen: View {
    let request: BurstFramesRequest
    /// Told what was kept after a delete, so the viewer can stand on it.
    var onDeleted: (([String]) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.appAccent) private var accent

    @State private var model: BurstFramesModel?

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
            let library = dependencies.bursts
            let photoLibrary = photoLibrary
            let made = BurstFramesModel(
                request: request,
                library: library,
                isLimited: photoLibrary.authorizationState == .limited,
                banner: dependencies.banner,
                deleteAssets: { ids in
                    try await photoLibrary.deleteAssets(PhotoLibraryService.fetchAssets(ids: ids))
                }
            )
            model = made
            await made.load()
        }
    }

    @ViewBuilder
    private func content(_ model: BurstFramesModel) -> some View {
        GeometryReader { proxy in
            let layout = CullLayout.forSize(proxy.size)
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
                    Spacer()
                case .ready:
                    bigFrame(model)
                    filmstrip(model, layout: layout)
                    deleteArea(model)
                }
            }
        }
        .background { keyButtons(model) }
    }

    // MARK: Top bar

    /// ✕ · `Frame 3 of 24` · Keep Only Suggested — in one row, so a long
    /// button never runs over the counter.
    private func topBar(_ model: BurstFramesModel) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: CullLayout.control, height: CullLayout.control)
                    .editorGlass(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(MarkCopy.close)
            Text(model.selection.count > 0 ? model.selection.title : "")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: model.selection.hasSuggestions ? .leading : .center)
            if model.selection.hasSuggestions {
                Button {
                    model.keepOnlySuggested()
                } label: {
                    Text("Keep Only Suggested", comment: "Burst frame picker: keep exactly the frames Photos suggested")
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
            } else {
                Color.clear.frame(width: CullLayout.control, height: CullLayout.control)
            }
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .frame(height: CullLayout.topBarHeight)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: Big frame

    private func bigFrame(_ model: BurstFramesModel) -> some View {
        let selection = model.selection
        let frame = selection.current
        let isKept = frame.map { selection.isKept($0.id) } ?? false
        return ZStack {
            if let frame {
                BurstBigFrame(asset: model.asset(for: frame.id), photoLibrary: photoLibrary)
                    .id(frame.id)
            }
        }
        // The labels and the tick sit on the photo, not in the letterbox.
        .aspectRatio(aspectRatio(of: frame.flatMap { model.asset(for: $0.id) }), contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if let frame {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if frame.isSuggested { chip(BurstSelection.suggestedTitle, fill: accent, text: .black) }
                    if frame.isPickedInPhotos { chip(BurstSelection.pickedInPhotosTitle, fill: .white.opacity(0.22), text: .white) }
                }
                .padding(CullLayout.edgeInset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            keepBadge(isKept: isKept, size: 30)
                .padding(CullLayout.edgeInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleKeepCurrent() }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { model.next() } else { model.previous() }
            }
        )
        .contextMenu {
            if let frame {
                Button {
                    model.keepOnly(frame.id)
                } label: {
                    Label(Self.keepOnlyTitle, systemImage: "checkmark.circle")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selection.accessibilityLabel(at: selection.currentIndex))
        .accessibilityAddTraits(isKept ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.toggleKeepCurrent() }
        .accessibilityAction(named: Text(Self.keepOnlyTitle)) {
            if let frame { model.keepOnly(frame.id) }
        }
        .sensoryFeedback(.selection, trigger: selection.keptIds)
    }

    private func aspectRatio(of asset: PHAsset?) -> CGFloat {
        guard let asset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1.5 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    static let cornerClearance: CGFloat = 24

    static var keepOnlyTitle: String {
        String(localized: "Keep Only This", comment: "Burst frame picker: keep this frame and no other")
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
        .allowsHitTesting(false)
    }

    // MARK: Filmstrip

    private func filmstrip(_ model: BurstFramesModel, layout: CullLayout) -> some View {
        let selection = model.selection
        return ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(selection.frames.enumerated()), id: \.element.id) { index, frame in
                        Button {
                            model.show(index)
                        } label: {
                            CullThumbnail(asset: model.asset(for: frame.id), photoLibrary: photoLibrary, side: layout.filmstripCell)
                                .frame(width: layout.filmstripCell, height: layout.filmstripCell)
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
                                .overlay {
                                    if index == selection.currentIndex {
                                        Rectangle().strokeBorder(.white, lineWidth: 2)
                                    }
                                }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .id(frame.id)
                        .accessibilityLabel(selection.accessibilityLabel(at: index))
                        .accessibilityAddTraits(index == selection.currentIndex ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.horizontal, CullLayout.edgeInset)
            }
            .scrollIndicators(.hidden)
            .frame(height: layout.filmstripHeight)
            .onChange(of: selection.currentIndex) { _, _ in
                guard let id = selection.current?.id else { return }
                withAnimation(AppTheme.Motion.standard) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MarkCopy.filmstrip)
    }

    // MARK: Delete

    private func deleteArea(_ model: BurstFramesModel) -> some View {
        let selection = model.selection
        return VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                Task { await delete(model) }
            } label: {
                Label(selection.deleteTitle, systemImage: "trash")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: CullLayout.controlRowWidth)
                    .frame(height: 48)
                    .background(Capsule().fill(Color.red))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!selection.canDelete || model.isDeleting)
            .opacity(selection.canDelete ? 1 : 0.35)
            .keyboardShortcut(.delete, modifiers: .command)
            Text(selection.deleteFootnote)
                .font(.caption)
                .foregroundStyle(EditorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.md)
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

/// The big frame's image: the best local rendition first, then the
/// screen-sized one.
private struct BurstBigFrame: View {
    let asset: PHAsset?
    let photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
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
