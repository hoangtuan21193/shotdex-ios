import SwiftUI

// MARK: - Music

/// Soundtrack controls: bundled track chips + Files import + None, then the
/// volume/fade sliders. Volume edits ride the audio-mix tier — the preview
/// keeps playing while they change.
struct VideoMusicPanel: View {
    @Bindable var model: VideoStudioModel
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                trackChips
                if model.recipe.music != nil {
                    musicSliders
                }
                EditorPlainSliderRow(
                    title: String(localized: "Video Vol."),
                    value: model.recipe.videoVolume,
                    range: 0...1,
                    isBipolar: false,
                    valueText: "\(Int(model.recipe.videoVolume * 100))",
                    isActive: false,
                    onBeginDrag: { model.beginUndoGroup() },
                    onDrag: { model.setVideoVolume($0) },
                    onEndDrag: { model.endUndoGroup() },
                    onReset: { model.pushUndo(); model.setVideoVolume(1) }
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private var selectedBundledID: String? {
        if case .bundled(let id)? = model.recipe.music?.source { return id }
        return nil
    }

    private var isImportedSelected: Bool {
        if case .imported? = model.recipe.music?.source { return true }
        return false
    }

    private var trackChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    model.setMusic(nil)
                } label: {
                    Label(String(localized: "None"), systemImage: "speaker.slash")
                        .font(EditorTheme.pillLabel)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: model.recipe.music == nil))

                ForEach(MusicTrackCatalog.availableTracks) { track in
                    Button {
                        model.setMusic(MusicSelection(source: .bundled(id: track.id)))
                    } label: {
                        Label(track.displayName, systemImage: "music.note")
                            .font(EditorTheme.pillLabel)
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: selectedBundledID == track.id))
                }

                Button {
                    onImport()
                } label: {
                    Label(importedLabel, systemImage: "square.and.arrow.down")
                        .font(EditorTheme.pillLabel)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: isImportedSelected))
            }
        }
    }

    private var importedLabel: String {
        if case .imported(_, let name)? = model.recipe.music?.source { return name }
        return String(localized: "Import…")
    }

    @ViewBuilder
    private var musicSliders: some View {
        let music = model.recipe.music
        EditorPlainSliderRow(
            title: String(localized: "Music"),
            value: music?.volume ?? 1,
            range: 0...1,
            isBipolar: false,
            valueText: "\(Int((music?.volume ?? 1) * 100))",
            isActive: false,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: { model.setMusicVolume($0) },
            onEndDrag: { model.endUndoGroup() },
            onReset: { model.pushUndo(); model.setMusicVolume(1) }
        )
        EditorPlainSliderRow(
            title: String(localized: "Fade In"),
            value: music?.fadeIn ?? 2,
            range: 0...8,
            isBipolar: false,
            valueText: String(format: "%.1fs", music?.fadeIn ?? 2),
            isActive: false,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: { model.setMusicFadeIn($0) },
            onEndDrag: { model.endUndoGroup() },
            onReset: { model.pushUndo(); model.setMusicFadeIn(2) }
        )
        EditorPlainSliderRow(
            title: String(localized: "Fade Out"),
            value: music?.fadeOut ?? 2,
            range: 0...8,
            isBipolar: false,
            valueText: String(format: "%.1fs", music?.fadeOut ?? 2),
            isActive: false,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: { model.setMusicFadeOut($0) },
            onEndDrag: { model.endUndoGroup() },
            onReset: { model.pushUndo(); model.setMusicFadeOut(2) }
        )
    }
}

// MARK: - Text

/// Text overlays on the shared overlay stack. No tokens (a multi-clip video
/// has no single EXIF source); each overlay's visible window is edited by
/// dragging its bar on the timeline's text track, not here.
struct VideoTextPanel: View {
    @Bindable var model: VideoStudioModel
    let onAddText: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onPickFont: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onAddText) {
                    Label(String(localized: "Add Text"), systemImage: "plus")
                        .font(EditorTheme.pillLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))

                ForEach(model.recipe.overlays) { timed in
                    overlayRow(timed.overlay)
                }

                if model.selectedOverlay != nil {
                    selectedOverlayControls
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private func overlayRow(_ overlay: PhotoOverlay) -> some View {
        let isSelected = model.selectedOverlayID == overlay.id
        return Button {
            model.selectedOverlayID = isSelected ? nil : overlay.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 12))
                Text(overlay.text.isEmpty ? String(localized: "Text") : overlay.text)
                    .font(EditorTheme.rowLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Button {
                        onEditText(overlay)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.deleteSelectedOverlay()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: EditorLayoutMetrics.editorRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? EditorTheme.activeRow : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedOverlayControls: some View {
        let overlay = model.selectedOverlay
        EditorPlainSliderRow(
            title: String(localized: "Size"),
            value: overlay?.size ?? 0.06,
            range: 0.02...0.3,
            isBipolar: false,
            valueText: String(format: "%.0f", (overlay?.size ?? 0.06) * 1000),
            isActive: false,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: { newValue in model.updateSelectedOverlay { $0.size = newValue } },
            onEndDrag: { model.endUndoGroup() },
            onReset: { model.pushUndo(); model.updateSelectedOverlay { $0.size = 0.06 } }
        )
        HStack(spacing: 8) {
            Button {
                onPickFont()
            } label: {
                Label(String(localized: "Font"), systemImage: "textformat.alt")
                    .font(EditorTheme.pillLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: false))

            ColorPicker(
                String(localized: "Color"),
                selection: Binding(
                    get: {
                        let fill = overlay?.fill ?? .white
                        return Color(red: fill.red, green: fill.green, blue: fill.blue)
                    },
                    set: { newColor in
                        let resolved = UIColor(newColor)
                        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
                        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        model.updateSelectedOverlay {
                            $0.fill = OverlayColor(red: Double(red), green: Double(green), blue: Double(blue))
                        }
                    }
                ),
                supportsOpacity: false
            )
            .font(EditorTheme.rowLabel)
            .foregroundStyle(EditorTheme.secondaryText)
        }
    }
}

// MARK: - Filter

/// One look for the whole video: a `PhotoFilter` strip + intensity, plus six
/// basic adjustments. All of it rides the videoComposition tier.
struct VideoFilterPanel: View {
    @Bindable var model: VideoStudioModel

    private static let adjustmentKinds: [PhotoAdjustmentKind] = [
        .exposure, .contrast, .saturation, .warmth, .brightness, .vignette,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                filterChips
                if model.recipe.filter != .original {
                    EditorPlainSliderRow(
                        title: String(localized: "Intensity"),
                        value: model.recipe.filterIntensity,
                        range: 0...1,
                        isBipolar: false,
                        valueText: "\(Int(model.recipe.filterIntensity * 100))",
                        isActive: false,
                        detent: 1,
                        onBeginDrag: { model.beginUndoGroup() },
                        onDrag: { model.setFilterIntensity($0) },
                        onEndDrag: { model.endUndoGroup() },
                        onReset: { model.pushUndo(); model.setFilterIntensity(1) }
                    )
                }
                ForEach(Self.adjustmentKinds, id: \.self) { kind in
                    adjustmentRow(kind)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoFilter.allCases) { filter in
                    Button(filter.displayName) {
                        model.setFilter(filter)
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: model.recipe.filter == filter))
                }
            }
        }
    }

    private func adjustmentRow(_ kind: PhotoAdjustmentKind) -> some View {
        let value = model.recipe.adjustments[kind]
        return EditorPlainSliderRow(
            title: kind.displayName,
            value: value,
            range: -1...1,
            isBipolar: true,
            valueText: String(format: "%+.0f", value * 100),
            isActive: false,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: { model.setAdjustment(kind, value: $0) },
            onEndDrag: { model.endUndoGroup() },
            onReset: { model.pushUndo(); model.setAdjustment(kind, value: 0) }
        )
    }
}
