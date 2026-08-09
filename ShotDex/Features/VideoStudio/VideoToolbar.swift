import SwiftUI

/// The bottom bar under the timeline. Shows the contextual icon toolbar when
/// no panel is open (root / clip-selected / text-selected variants are
/// derived from the selection, never stored), or a detail panel with a
/// checkmark header when `model.activePanel` is set.
struct VideoBottomArea: View {
    @Bindable var model: VideoStudioModel
    let onImportMusic: () -> Void
    let onAddText: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onPickFont: () -> Void

    static let toolbarHeight: CGFloat = 56
    static let panelHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(EditorTheme.panelTopHairline)
                .frame(height: 1)
            if let panel = model.activePanel {
                VideoDetailPanel(
                    panel: panel,
                    model: model,
                    onImportMusic: onImportMusic,
                    onAddText: onAddText,
                    onEditText: onEditText,
                    onPickFont: onPickFont
                )
                .frame(height: Self.panelHeight)
            } else {
                VideoToolbar(model: model, onAddText: onAddText, onEditText: onEditText)
                    .frame(height: Self.toolbarHeight)
            }
        }
        .background(EditorTheme.panelSolid)
        .animation(EditorTheme.panelSpring, value: model.activePanel)
    }
}

// MARK: - Toolbar

struct VideoToolbar: View {
    @Bindable var model: VideoStudioModel
    let onAddText: () -> Void
    let onEditText: (PhotoOverlay) -> Void

    private enum Variant {
        case root, clipSelected, textSelected
    }

    private var variant: Variant {
        if model.selectedOverlayID != nil { return .textSelected }
        if model.selectedClipID != nil { return .clipSelected }
        return .root
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                switch variant {
                case .root:
                    rootButtons
                case .clipSelected:
                    clipButtons
                case .textSelected:
                    textButtons
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func open(_ panel: VideoStudioModel.TimelinePanel) {
        withAnimation(EditorTheme.panelSpring) { model.activePanel = panel }
    }

    /// Edit/Effect from the root act on the clip under the playhead.
    private func selectClipUnderPlayhead() {
        guard let index = VideoTimelineMath.clipIndex(
            at: model.currentTime, placements: model.clipPlacements
        ) else { return }
        model.selectedClipID = model.recipe.clips[index].id
    }

    @ViewBuilder
    private var rootButtons: some View {
        toolButton("Edit", systemImage: "scissors") {
            selectClipUnderPlayhead()
            if model.selectedClipID != nil { open(.clipEdit) }
        }
        toolButton("Effect", systemImage: "sparkles") {
            selectClipUnderPlayhead()
            if model.selectedClipID != nil { open(.effect) }
        }
        toolButton("Text", systemImage: "textformat") { open(.text) }
        toolButton("Filter", systemImage: "camera.filters") { open(.filter) }
        toolButton("Music", systemImage: "music.note") { open(.music) }
        if model.mode == .singleVideo {
            toolButton("Rotate", systemImage: "rotate.right") {
                model.pushUndo()
                model.rotateClockwise()
            }
        }
    }

    @ViewBuilder
    private var clipButtons: some View {
        backButton { model.selectedClipID = nil }
        if let clip = model.selectedClip {
            toolButton(
                clip.kind == .video ? "Trim" : "Duration",
                systemImage: clip.kind == .video ? "timeline.selection" : "clock"
            ) { open(.clipEdit) }
            toolButton(
                "Effect",
                systemImage: "sparkles",
                isActive: clip.effect != .none
            ) { open(.effect) }
            if clip.kind == .video {
                toolButton(
                    "Mute",
                    systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                    isActive: clip.isMuted
                ) {
                    model.pushUndo()
                    model.setMuted(!clip.isMuted, for: clip.id)
                }
            }
            if model.mode == .singleVideo {
                toolButton("Rotate", systemImage: "rotate.right") {
                    model.pushUndo()
                    model.rotateClockwise()
                }
            }
            if model.mode == .multiClip, model.recipe.clips.count > 1 {
                toolButton("Delete", systemImage: "trash", role: .destructive) {
                    model.pushUndo()
                    model.deleteClip(clip.id)
                }
            }
        }
    }

    @ViewBuilder
    private var textButtons: some View {
        backButton { model.selectedOverlayID = nil }
        if let overlay = model.selectedOverlay {
            toolButton("Edit", systemImage: "pencil") { onEditText(overlay) }
            toolButton("Style", systemImage: "textformat.alt") { open(.text) }
            toolButton("Delete", systemImage: "trash", role: .destructive) {
                model.pushUndo()
                model.deleteSelectedOverlay()
            }
        }
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(EditorTheme.panelSpring) { action() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 36, height: VideoBottomArea.toolbarHeight)
        }
        .buttonStyle(.plain)
    }

    private func toolButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        isActive: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(EditorTheme.tabLabel)
            }
            .foregroundStyle(
                role == .destructive
                    ? Color.red.opacity(0.9)
                    : isActive ? EditorTheme.accent : EditorTheme.dimText
            )
            .frame(width: 56, height: VideoBottomArea.toolbarHeight)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail panel

/// A 220 pt panel replacing the toolbar: 36 pt header (title + ✓ to close)
/// over the panel content. Filter/Music/Text reuse the existing panels.
struct VideoDetailPanel: View {
    let panel: VideoStudioModel.TimelinePanel
    @Bindable var model: VideoStudioModel
    let onImportMusic: () -> Void
    let onAddText: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onPickFont: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(EditorTheme.panelDivider)
                .frame(height: 1)
            content
                .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(EditorTheme.maskTitle)
                .foregroundStyle(.white)
            Spacer()
            Button {
                withAnimation(EditorTheme.panelSpring) { model.activePanel = nil }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 40, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .frame(height: 36)
    }

    private var title: String {
        switch panel {
        case .clipEdit:
            model.selectedClip?.kind == .photo
                ? String(localized: "Duration")
                : String(localized: "Trim")
        case .effect: String(localized: "Effect")
        case .transition: String(localized: "Transition")
        case .text: String(localized: "Text")
        case .filter: String(localized: "Filter")
        case .music: String(localized: "Music")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .clipEdit:
            clipEditContent
        case .effect:
            effectContent
        case .transition(let index):
            transitionContent(index)
        case .text:
            VideoTextPanel(
                model: model,
                onAddText: onAddText,
                onEditText: onEditText,
                onPickFont: onPickFont
            )
        case .filter:
            VideoFilterPanel(model: model)
        case .music:
            VideoMusicPanel(model: model, onImport: onImportMusic)
        }
    }

    // MARK: Clip edit (trim / duration / mute / rotate)

    @ViewBuilder
    private var clipEditContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let clip = model.selectedClip {
                    switch clip.kind {
                    case .photo:
                        EditorPlainSliderRow(
                            title: String(localized: "Duration"),
                            value: clip.photoDuration,
                            range: VideoClip.photoDurationRange,
                            isBipolar: false,
                            valueText: String(format: "%.1fs", clip.photoDuration),
                            isActive: false,
                            onBeginDrag: { model.beginUndoGroup() },
                            onDrag: { model.setPhotoDuration($0, for: clip.id) },
                            onEndDrag: { model.endUndoGroup() },
                            onReset: {
                                model.pushUndo()
                                model.setPhotoDuration(VideoClip.defaultPhotoDuration, for: clip.id)
                            }
                        )
                    case .video:
                        VideoTrimBar(model: model, clip: clip)
                        EditorToggleRow(
                            title: String(localized: "Mute clip audio"),
                            isOn: clip.isMuted,
                            onChange: {
                                model.pushUndo()
                                model.setMuted($0, for: clip.id)
                            }
                        )
                    }
                    if model.mode == .singleVideo {
                        Button {
                            model.pushUndo()
                            model.rotateClockwise()
                        } label: {
                            Label(String(localized: "Rotate"), systemImage: "rotate.right")
                                .font(EditorTheme.pillLabel)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(EditorChipButtonStyle(isSelected: model.recipe.quarterTurns != 0))
                    }
                } else {
                    Text("Select a clip on the timeline.")
                        .font(EditorTheme.rowLabel)
                        .foregroundStyle(EditorTheme.dimText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: Effect picker

    @ViewBuilder
    private var effectContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let clip = model.selectedClip {
                    chipGrid(VideoClipEffect.allCases, id: \.self) { effect in
                        Button(effect.displayName) {
                            model.pushUndo()
                            model.setEffect(effect, for: clip.id)
                        }
                        .buttonStyle(EditorChipButtonStyle(isSelected: clip.effect == effect))
                    }
                } else {
                    Text("Select a clip on the timeline.")
                        .font(EditorTheme.rowLabel)
                        .foregroundStyle(EditorTheme.dimText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: Transition picker

    @ViewBuilder
    private func transitionContent(_ index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.recipe.transitions.indices.contains(index) {
                    let transition = model.recipe.transitions[index]
                    chipGrid(VideoTransitionKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) {
                            model.pushUndo()
                            model.setTransition(
                                VideoBoundaryTransition(kind: kind, duration: transition.duration),
                                at: index
                            )
                        }
                        .buttonStyle(EditorChipButtonStyle(isSelected: transition.kind == kind))
                    }
                    if transition.kind != .none {
                        EditorPlainSliderRow(
                            title: String(localized: "Duration"),
                            value: transition.duration,
                            range: VideoBoundaryTransition.durationRange,
                            isBipolar: false,
                            valueText: String(format: "%.1fs", transition.duration),
                            isActive: false,
                            onBeginDrag: { model.beginUndoGroup() },
                            onDrag: {
                                model.setTransition(
                                    VideoBoundaryTransition(kind: transition.kind, duration: $0),
                                    at: index
                                )
                            },
                            onEndDrag: { model.endUndoGroup() },
                            onReset: {
                                model.pushUndo()
                                model.setTransition(
                                    VideoBoundaryTransition(kind: transition.kind, duration: 0.5),
                                    at: index
                                )
                            }
                        )
                        Button {
                            model.pushUndo()
                            model.setAllTransitions(transition)
                        } label: {
                            Label(String(localized: "Apply to All"), systemImage: "square.on.square")
                                .font(EditorTheme.pillLabel)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(EditorChipButtonStyle(isSelected: false))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    /// Wrapping chip rows — `VideoClipEffect`/`VideoTransitionKind` overflow a
    /// single line, and a horizontal strip hides the tail.
    private func chipGrid<Item, ID: Hashable>(
        _ items: [Item],
        id: KeyPath<Item, ID>,
        @ViewBuilder chip: @escaping (Item) -> some View
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: id) { item in
                chip(item)
            }
        }
    }
}
