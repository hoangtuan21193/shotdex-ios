import SwiftUI

/// The sheet-free callbacks the inspector fires for actions that need a picker
/// or a full-screen editor the screen owns.
struct VideoInspectorActions {
    var onExport: () -> Void
    var onBack: () -> Void
    var onAddMedia: () -> Void
    var onReplaceClip: () -> Void
    var onAddSticker: () -> Void
    var onChooseMusic: () -> Void
    var onEditText: (PhotoOverlay) -> Void
    var onPickFont: () -> Void
}

/// The 260pt inspector (spec §5). Four tiers of fixed height — title 36 /
/// params 102 / icon command band 62 / export 50 — over a 10pt safe area, so
/// the panel never changes height when the selection changes.
struct VideoInspectorPanel: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    var body: some View {
        VStack(spacing: 0) {
            // The Project (none) state hides the title row — its label was
            // redundant (ratio + clip count already show elsewhere) — and hands
            // that height to the param zone so the tiers still sum to 260.
            if model.inspectorTarget != .none {
                titleRow
                    .frame(height: VideoStudioMetrics.panelTitleHeight)
                    .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
            }
            paramZone
                .frame(height: paramZoneHeight)
            VideoCommandBand(commands: commands)
            exportRow
                .frame(height: VideoStudioMetrics.panelExportHeight)
            Color.clear.frame(height: VideoStudioMetrics.panelSafeAreaInset)
        }
        .frame(height: VideoStudioMetrics.panelHeight)
        .background(EditorTheme.panelSolid)
        // Top edge hairline drawn as an overlay so it costs no layout height —
        // the tiers sum to exactly 260 (spec §8 acceptance).
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1) }
        .animation(EditorTheme.animation, value: model.inspectorTarget)
    }

    /// Param-zone height: the standard tier, plus the reclaimed title-row height
    /// in the none state where the title row is hidden (keeps the panel at 260).
    private var paramZoneHeight: CGFloat {
        model.inspectorTarget == .none
            ? VideoStudioMetrics.panelParamHeight + VideoStudioMetrics.panelTitleHeight
            : VideoStudioMetrics.panelParamHeight
    }

    // MARK: Title row

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(titleText).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let subtitle = subtitleText {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(EditorTheme.dimText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            titleButtons
        }
        .padding(.horizontal, 14)
    }

    private var badge: some View {
        let (symbol, active) = badgeSymbol
        return RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
            .fill(active ? EditorTheme.timelineSelection.opacity(0.18) : Color.white.opacity(0.06))
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? EditorTheme.timelineSelection : EditorTheme.dimText)
            }
    }

    private var badgeSymbol: (String, Bool) {
        switch model.inspectorTarget {
        case .clip:
            switch model.selectedClip?.kind {
            case .video: ("film", true)
            case .freeze: ("snowflake", true)
            default: ("photo", true)
            }
        case .text: (model.selectedOverlay?.kind == .image ? "photo" : "textformat", true)
        case .music: ("music.note", true)
        case .none: ("slider.horizontal.3", false)
        }
    }

    private var titleText: String {
        switch model.inspectorTarget {
        case .clip:
            switch model.selectedClip?.kind {
            case .video: String(localized: "Video")
            case .freeze: String(localized: "Freeze")
            default: String(localized: "Photo")
            }
        case .text: model.selectedOverlay?.kind == .image
            ? String(localized: "Sticker")
            : (model.selectedOverlay?.text.isEmpty == false ? model.selectedOverlay!.text : String(localized: "Text"))
        case .music: musicName
        case .none: String(localized: "Project")
        }
    }

    private var subtitleText: String? {
        switch model.inspectorTarget {
        case .clip:
            guard let clip = model.selectedClip else { return nil }
            return String(format: "%.1fs", clip.effectiveDuration)
        case .text: return nil
        case .music: return model.recipe.music?.loops == true ? String(localized: "Loops") : String(localized: "Plays once")
        case .none: return "\(model.recipe.clips.count) clips · \(model.recipe.aspect.displayName)"
        }
    }

    @ViewBuilder
    private var titleButtons: some View {
        switch model.inspectorTarget {
        case .clip:
            if model.mode == .multiClip, model.recipe.clips.count > 1 {
                titleButton("trash", destructive: true) {
                    if let id = model.selectedClipID { model.pushUndo(); model.deleteClip(id) }
                }
            }
        case .text:
            titleButton("trash", destructive: true) {
                model.pushUndo(); model.deleteSelectedOverlay()
            }
        case .music:
            titleButton("trash", destructive: true) {
                model.pushUndo(); model.setMusic(nil)
            }
        case .none:
            EmptyView()
        }
    }

    private func titleButton(_ symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(destructive ? EditorTheme.timelineDestructive : .white)
                .frame(width: VideoStudioMetrics.inspectorTitleButton, height: VideoStudioMetrics.inspectorTitleButton)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destructive ? "Delete" : symbol)
    }

    // MARK: Param zone

    @ViewBuilder
    private var paramZone: some View {
        switch model.inspectorTarget {
        case .clip: clipParams
        case .text: textParams
        case .music: musicParams
        case .none: noneParams
        }
    }

    @ViewBuilder
    private var clipParams: some View {
        if let clip = model.selectedClip {
            VStack(spacing: 0) {
                switch clip.kind {
                case .video:
                    durationSlider(clip)
                    InspectorSlider(
                        label: "Speed", value: clip.speed, range: VideoClip.speedRange,
                        valueText: String(format: "%.2g×", clip.speed), model: model,
                        set: { model.setSpeed($0, for: clip.id) },
                        reset: { model.pushUndo(); model.setSpeed(1, for: clip.id) }
                    )
                    InspectorSlider(
                        label: "Volume", value: model.recipe.videoVolume, range: 0...1,
                        valueText: "\(Int(model.recipe.videoVolume * 100))", model: model,
                        set: { model.setVideoVolume($0) },
                        reset: { model.pushUndo(); model.setVideoVolume(1) }
                    )
                case .photo, .freeze:
                    durationSlider(clip)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func durationSlider(_ clip: VideoClip) -> some View {
        let source = clip.sourceDuration ?? VideoClip.photoDurationRange.upperBound
        let range: ClosedRange<Double> = clip.kind == .video
            ? 0.5...max(0.6, (source - clip.trimStart) / max(clip.speed, VideoClip.speedRange.lowerBound))
            : VideoClip.photoDurationRange
        return InspectorSlider(
            label: "Duration", value: clip.effectiveDuration, range: range,
            valueText: String(format: "%.1fs", clip.effectiveDuration), model: model,
            set: { newValue in
                if clip.kind == .video {
                    let end = clip.trimStart + newValue * max(clip.speed, VideoClip.speedRange.lowerBound)
                    model.setTrim(start: clip.trimStart, end: end, for: clip.id)
                } else {
                    model.setPhotoDuration(newValue, for: clip.id)
                }
            },
            reset: {
                model.pushUndo()
                if clip.kind == .video {
                    model.setTrim(start: clip.trimStart, end: source, for: clip.id)
                } else {
                    model.setPhotoDuration(VideoClip.defaultPhotoDuration, for: clip.id)
                }
            }
        )
    }

    @ViewBuilder
    private var textParams: some View {
        if let overlay = model.selectedOverlay {
            VStack(spacing: 0) {
                InspectorSlider(
                    label: "Size", value: overlay.size, range: 0.02...0.4,
                    valueText: String(format: "%.0f", overlay.size * 1000), model: model,
                    set: { newValue in model.updateSelectedOverlay { $0.size = newValue } },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.size = overlay.kind == .image ? 0.25 : 0.05 } }
                )
                InspectorSlider(
                    label: "Opacity", value: overlay.opacity, range: 0...1,
                    valueText: "\(Int(overlay.opacity * 100))", model: model,
                    set: { newValue in model.updateSelectedOverlay { $0.opacity = newValue } },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.opacity = 1 } }
                )
                startsAtSlider(overlay)
                Spacer(minLength: 0)
            }
        }
    }

    private func startsAtSlider(_ overlay: PhotoOverlay) -> some View {
        let timed = model.selectedTimedOverlay
        let start = timed?.start ?? 0
        return InspectorSlider(
            label: "Starts at", value: start, range: 0...max(0.1, model.totalDuration),
            valueText: String(format: "%.1fs", start), model: model,
            set: { newValue in model.setOverlayTiming(start: newValue, duration: timed?.duration, forOverlay: overlay.id) },
            reset: { model.pushUndo(); model.setOverlayTiming(start: 0, duration: timed?.duration, forOverlay: overlay.id) }
        )
    }

    @ViewBuilder
    private var musicParams: some View {
        let music = model.recipe.music
        VStack(spacing: 0) {
            InspectorSlider(
                label: "Volume", value: music?.volume ?? 1, range: 0...1,
                valueText: "\(Int((music?.volume ?? 1) * 100))", model: model,
                set: { model.setMusicVolume($0) },
                reset: { model.pushUndo(); model.setMusicVolume(1) }
            )
            InspectorSlider(
                label: "Fade in", value: music?.fadeIn ?? 2, range: 0...8,
                valueText: String(format: "%.1fs", music?.fadeIn ?? 2), model: model,
                set: { model.setMusicFadeIn($0) },
                reset: { model.pushUndo(); model.setMusicFadeIn(2) }
            )
            InspectorSlider(
                label: "Fade out", value: music?.fadeOut ?? 2, range: 0...8,
                valueText: String(format: "%.1fs", music?.fadeOut ?? 2), model: model,
                set: { model.setMusicFadeOut($0) },
                reset: { model.pushUndo(); model.setMusicFadeOut(2) }
            )
        }
    }

    @ViewBuilder
    private var noneParams: some View {
        switch model.inspectorNoneTool {
        case .root:
            VStack(spacing: 0) {
                RatioStrip(model: model).frame(height: 34)
                InspectorSlider(
                    label: "Master", value: model.recipe.masterVolume, range: 0...1,
                    valueText: "\(Int(model.recipe.masterVolume * 100))", model: model,
                    set: { model.setMasterVolume($0) },
                    reset: { model.pushUndo(); model.setMasterVolume(1) }
                )
                BackgroundStrip(model: model).frame(height: 34)
            }
        case .filters:
            VStack(spacing: 0) {
                FilterStrip(model: model).frame(height: 34)
                if model.recipe.filter != .original {
                    InspectorSlider(
                        label: "Intensity", value: model.recipe.filterIntensity, range: 0...1,
                        valueText: "\(Int(model.recipe.filterIntensity * 100))", detent: 1, model: model,
                        set: { model.setFilterIntensity($0) },
                        reset: { model.pushUndo(); model.setFilterIntensity(1) }
                    )
                }
                Spacer(minLength: 0)
            }
        case .effects:
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach([PhotoAdjustmentKind.exposure, .contrast, .saturation, .warmth, .brightness, .vignette], id: \.self) { kind in
                        let value = model.recipe.adjustments[kind]
                        InspectorSlider(
                            label: kind.displayName, value: value, range: -1...1,
                            valueText: String(format: "%+.0f", value * 100), anchor: 0, notch: true, detent: 0, model: model,
                            set: { model.setAdjustment(kind, value: $0) },
                            reset: { model.pushUndo(); model.setAdjustment(kind, value: 0) }
                        )
                    }
                }
            }
        }
    }

    // MARK: Commands

    private var commands: [VideoCommand] {
        switch model.inspectorTarget {
        case .clip: clipCommands
        case .text: textCommands
        case .music: musicCommands
        case .none: noneCommands
        }
    }

    private var clipCommands: [VideoCommand] {
        guard let clip = model.selectedClip else { return [] }
        var list: [VideoCommand] = [
            VideoCommand(title: "Split", systemImage: "scissors") { model.splitClipUnderPlayhead() },
        ]
        if clip.kind == .video {
            list.append(VideoCommand(title: "Speed", systemImage: "speedometer") {})
            list.append(VideoCommand(
                title: clip.isMuted ? "Unmute" : "Mute",
                systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2"
            ) { model.pushUndo(); model.setMuted(!clip.isMuted, for: clip.id) })
        }
        list.append(VideoCommand(title: "Animate", systemImage: "wand.and.stars") { animateMenu(clip) })
        list.append(VideoCommand(title: "Replace", systemImage: "arrow.triangle.2.circlepath", action: actions.onReplaceClip))
        if clip.kind != .photo {
            list.append(VideoCommand(title: "Freeze", systemImage: "snowflake") { model.freezeUnderPlayhead() })
        }
        if model.mode == .singleVideo {
            list.append(VideoCommand(title: "Rotate", systemImage: "rotate.right") { model.pushUndo(); model.rotateClockwise() })
        }
        if model.mode == .multiClip, model.recipe.clips.count > 1 {
            list.append(VideoCommand(title: "Delete", systemImage: "trash", tint: .destructive) {
                model.pushUndo(); model.deleteClip(clip.id)
            })
        }
        return list
    }

    /// Cycle the clip's motion effect (Animate → next VideoClipEffect). A menu
    /// would need a sheet; cycling keeps it inline and sheet-free.
    private func animateMenu(_ clip: VideoClip) {
        let all = VideoClipEffect.allCases
        let current = all.firstIndex(of: clip.effect) ?? 0
        let next = all[(current + 1) % all.count]
        model.pushUndo()
        model.setEffect(next, for: clip.id)
    }

    private var textCommands: [VideoCommand] {
        guard let overlay = model.selectedOverlay else { return [] }
        if overlay.kind == .image {
            return [
                VideoCommand(title: "Copy", systemImage: "plus.square.on.square") { model.duplicateSelectedOverlay() },
                VideoCommand(title: "Delete", systemImage: "trash", tint: .destructive) { model.pushUndo(); model.deleteSelectedOverlay() },
            ]
        }
        return [
            VideoCommand(title: "Edit", systemImage: "pencil") { actions.onEditText(overlay) },
            VideoCommand(title: "Font", systemImage: "textformat.alt", action: actions.onPickFont),
            VideoCommand(title: "Bold", systemImage: "bold", tint: overlay.isBold ? .accent : .normal) {
                model.pushUndo(); model.updateSelectedOverlay { $0.isBold.toggle() }
            },
            VideoCommand(title: "Copy", systemImage: "plus.square.on.square") { model.duplicateSelectedOverlay() },
            VideoCommand(title: "Delete", systemImage: "trash", tint: .destructive) { model.pushUndo(); model.deleteSelectedOverlay() },
        ]
    }

    private var musicCommands: [VideoCommand] {
        let loops = model.recipe.music?.loops ?? true
        return [
            VideoCommand(title: loops ? "Loop On" : "Loop Off", systemImage: loops ? "repeat" : "repeat.1", tint: loops ? .accent : .normal) {
                model.setMusicLoops(!loops)
            },
            VideoCommand(title: "Replace", systemImage: "arrow.triangle.2.circlepath", action: actions.onChooseMusic),
            VideoCommand(title: "Delete", systemImage: "trash", tint: .destructive) { model.pushUndo(); model.setMusic(nil) },
        ]
    }

    private var noneCommands: [VideoCommand] {
        [
            VideoCommand(title: "Add", systemImage: "plus", tint: .accent, action: actions.onAddMedia),
            VideoCommand(title: "Audio", systemImage: "music.note", action: actions.onChooseMusic),
            VideoCommand(title: "Text", systemImage: "textformat") { model.addTextOverlay(String(localized: "Text"), at: model.currentTime) },
            VideoCommand(title: "Overlay", systemImage: "photo.badge.plus", action: actions.onAddSticker),
            VideoCommand(title: "Effects", systemImage: "slider.horizontal.3", tint: model.inspectorNoneTool == .effects ? .accent : .normal) { model.showNoneTool(model.inspectorNoneTool == .effects ? .root : .effects) },
            VideoCommand(title: "Filters", systemImage: "camera.filters", tint: model.inspectorNoneTool == .filters ? .accent : .normal) { model.showNoneTool(model.inspectorNoneTool == .filters ? .root : .filters) },
            VideoCommand(title: "Ratio", systemImage: "aspectratio") { model.showNoneTool(.root) },
        ]
    }

    // MARK: Export row

    private var exportRow: some View {
        HStack(spacing: 12) {
            Button(action: actions.onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.1fs · %@ · 30fps", model.totalDuration, model.recipe.renderPreset.displayName))
                    .font(.system(size: 11).monospacedDigit())
                Text("~\(sizeText)")
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(EditorTheme.dimText)

            Spacer(minLength: 0)

            Button(action: actions.onExport) {
                Text("Export")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Capsule().fill(EditorTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: model.estimatedExportBytes, countStyle: .file)
    }

    private var musicName: String {
        switch model.recipe.music?.source {
        case .bundled(let id): MusicTrackCatalog.track(id: id)?.displayName ?? String(localized: "Music")
        case .imported(_, let name): name
        case nil: String(localized: "Music")
        }
    }
}

// MARK: - Inspector slider (EditorValueSlider + undo grouping)

/// Wraps the editor's one slider with the studio's undo grouping so every param
/// row reads and behaves like the photo editor's.
private struct InspectorSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    var anchor: Double = 0
    var notch = false
    var detent: Double?
    let model: VideoStudioModel
    let set: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        EditorValueSlider(
            label: label, value: value, range: range, valueText: valueText,
            isActive: false, anchor: anchor, showsAnchorNotch: notch, detent: detent,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: set,
            onEndDrag: { _, _, _ in model.endUndoGroup() },
            onReset: reset
        )
    }
}

// MARK: - Ratio / background / filter strips

private struct RatioStrip: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        HStack(spacing: 8) {
            Text("RATIO").font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
                .foregroundStyle(EditorTheme.secondaryText).frame(width: 88, alignment: .leading)
            ForEach(VideoAspect.allCases) { aspect in
                let selected = model.recipe.aspect == aspect
                Button { model.setAspect(aspect) } label: {
                    Text(aspect.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .black : .white)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(selected ? EditorTheme.accent : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }
}

private struct BackgroundStrip: View {
    @Bindable var model: VideoStudioModel

    private static let swatches: [OverlayColor] = [.black, OverlayColor(white: 0.5), .white]

    var body: some View {
        HStack(spacing: 8) {
            Text("BACKGROUND").font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
                .foregroundStyle(EditorTheme.secondaryText).frame(width: 88, alignment: .leading)
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                let selected = model.recipe.background == swatch
                Button { model.pushUndo(); model.setBackground(swatch) } label: {
                    Circle()
                        .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 24, height: 24)
                        .overlay { Circle().strokeBorder(selected ? EditorTheme.accent : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1) }
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: Binding(
                get: {
                    let c = model.recipe.background
                    return Color(red: c.red, green: c.green, blue: c.blue)
                },
                set: { newColor in
                    let resolved = UIColor(newColor)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                    model.setBackground(OverlayColor(red: Double(r), green: Double(g), blue: Double(b)))
                }
            ), supportsOpacity: false)
            .labelsHidden()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }
}

private struct FilterStrip: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoFilter.allCases) { filter in
                    let selected = model.recipe.filter == filter
                    Button { model.setFilter(filter) } label: {
                        Text(filter.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? .black : .white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(selected ? EditorTheme.accent : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}
