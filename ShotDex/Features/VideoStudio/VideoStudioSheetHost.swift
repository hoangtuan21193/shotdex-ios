import SwiftUI
import ShotDexKit

/// The callbacks the sheets fire for actions that need a picker or a full-screen
/// editor the screen owns.
struct VideoInspectorActions {
    var onExport: () -> Void
    var onBack: () -> Void
    var onAddMedia: () -> Void
    var onReplaceClip: () -> Void
    var onAddText: () -> Void
    var onAddSticker: () -> Void
    var onAddMusic: () -> Void
    var onReplaceMusic: (UUID) -> Void
    var onEditText: (PhotoOverlay) -> Void
    var onPickFont: () -> Void
}

/// The contextual bottom sheet: a title row naming what is selected, the params
/// for it, and its command band. One sheet reskins for every target — selecting
/// a different object swaps the content in place rather than dismissing and
/// re-presenting. With nothing selected the sheet carries a project-wide tool
/// instead (ratio, filter, adjustments, master volume, background).
struct VideoStudioSheetHost: View {
    /// The same contents in the two shapes the window can give them.
    enum Layout {
        /// Full width, fixed tiers: the phone's band, and the panel docked
        /// under the timeline on a portrait tablet.
        case band
        /// A narrow column beside the stage, as Final Cut, LumaFusion and
        /// Resolve all put their inspector on a wide screen. Nothing is a
        /// fixed height here — a column is read top to bottom and scrolls.
        case column
    }

    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    var layout: Layout = .band

    var body: some View {
        Group {
            switch layout {
            case .band: bandBody
            case .column: columnBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorTheme.panelSolid)
        .animation(EditorTheme.animation, value: model.inspectorTarget)
        .animation(EditorTheme.animation, value: model.activeGlobalTool)
    }

    private var bandBody: some View {
        VStack(spacing: 0) {
            titleRow
                .frame(height: VideoStudioMetrics.sheetTitleHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
            paramZone
                .frame(height: VideoStudioMetrics.sheetParamHeight)
            if !commands.isEmpty {
                VideoCommandBand(commands: commands)
            }
            Spacer(minLength: 0)
        }
    }

    private var columnBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                titleRow
                    .frame(minHeight: VideoStudioMetrics.sheetTitleHeight)
                    .padding(.top, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
                paramZone
                    .padding(.top, 10)
                if !commands.isEmpty {
                    VideoCommandBand(commands: commands, wraps: true)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
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
        case .none: (model.activeGlobalTool?.systemImage ?? "slider.horizontal.3", false)
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
        case .music: model.selectedMusicTrack?.displayName ?? String(localized: "Music")
        case .none: model.activeGlobalTool?.title ?? String(localized: "Project")
        }
    }

    private var subtitleText: String? {
        switch model.inspectorTarget {
        case .clip:
            guard let clip = model.selectedClip else { return nil }
            return String(format: "%.1fs", clip.effectiveDuration)
        case .text: return nil
        case .music:
            guard let music = model.selectedMusicTrack else { return nil }
            return String(format: "%.1fs → %.1fs", music.start, music.end)
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
                if let id = model.selectedMusicID { model.removeMusicTrack(id) }
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
        case .none: globalParams
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
                    ClipEffectRow(selected: clip.effect) { effect in
                        guard effect != clip.effect else { return }
                        model.pushUndo()
                        model.setEffect(effect, for: clip.id)
                    }
                    .padding(.top, 6)
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
            switch model.inspectorTextTool {
            case .transform: transformParams(overlay)
            case .font: fontParams(overlay)
            case .color: colorParams(overlay)
            case .align: alignParams(overlay)
            case .style: styleParams(overlay)
            case .animate: animateParams(overlay)
            }
        }
    }

    @ViewBuilder
    private func transformParams(_ overlay: PhotoOverlay) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Content first: editing the words is the commonest reason to
                // open a caption, so it never hides behind a command.
                if overlay.kind == .text {
                    OverlayTextField(model: model, overlay: overlay, onExpand: { actions.onEditText(overlay) })
                }
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
            }
        }
    }

    /// Typeface plus the two weights that belong with it — Bold and Italic are
    /// font choices, not standalone commands.
    private func fontParams(_ overlay: PhotoOverlay) -> some View {
        VStack(spacing: 10) {
            Button(action: actions.onPickFont) {
                HStack(spacing: 8) {
                    Image(systemName: "textformat.alt").font(.system(size: 14, weight: .medium))
                    Text(overlay.fontFamilyName.isEmpty ? String(localized: "System") : overlay.fontFamilyName)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.dimText)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(Rectangle().inset(by: VideoStudioMetrics.fontButtonHitInset))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                fontToggle("Bold", "bold", isOn: overlay.isBold) {
                    model.pushUndo(); model.updateSelectedOverlay { $0.isBold.toggle() }
                }
                fontToggle("Italic", "italic", isOn: overlay.isItalic) {
                    model.pushUndo(); model.updateSelectedOverlay { $0.isItalic.toggle() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func fontToggle(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(isOn ? EditorTheme.accent : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(isOn ? EditorTheme.accent.opacity(0.18) : Color.white.opacity(0.05))
            )
            .contentShape(Rectangle().inset(by: VideoStudioMetrics.fontToggleHitInset))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Fill colour swatches + opacity. No system `ColorPicker` (the app builds
    /// colour UI by hand everywhere), and no custom wheel — the compact sheet keeps
    /// to the swatches a caption is nearly always one of.
    private func colorParams(_ overlay: PhotoOverlay) -> some View {
        VStack(spacing: 0) {
            OverlaySwatchRow(model: model, selected: overlay.fill) { color in
                model.updateSelectedOverlay { $0.fill = color }
            }
            InspectorSlider(
                label: "Opacity", value: overlay.opacity, range: 0...1,
                valueText: "\(Int(overlay.opacity * 100))", model: model,
                set: { newValue in model.updateSelectedOverlay { $0.opacity = newValue } },
                reset: { model.pushUndo(); model.updateSelectedOverlay { $0.opacity = 1 } }
            )
            Spacer(minLength: 0)
        }
    }

    private func alignParams(_ overlay: PhotoOverlay) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                OverlayAlignmentRow(model: model, selected: overlay.alignment)
                InspectorSlider(
                    label: "Tracking", value: overlay.tracking, range: -0.1...0.4,
                    valueText: String(format: "%+.0f", overlay.tracking * 100),
                    anchor: 0, notch: true, detent: 0, model: model,
                    set: { newValue in model.updateSelectedOverlay { $0.tracking = newValue } },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.tracking = 0 } }
                )
                InspectorSlider(
                    label: "Line spacing", value: overlay.lineSpacing, range: 0...0.6,
                    valueText: String(format: "%.0f", overlay.lineSpacing * 100), model: model,
                    set: { newValue in model.updateSelectedOverlay { $0.lineSpacing = newValue } },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.lineSpacing = 0.15 } }
                )
            }
        }
    }

    /// Outline thickness + colour and a drop shadow — the two ways to lift a
    /// caption off a busy frame.
    private func styleParams(_ overlay: PhotoOverlay) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                InspectorSlider(
                    label: "Outline", value: overlay.outlineWidth, range: 0...0.15,
                    valueText: String(format: "%.0f", overlay.outlineWidth * 100), model: model,
                    set: { newValue in model.updateSelectedOverlay { $0.outlineWidth = newValue } },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.outlineWidth = 0 } }
                )
                if overlay.outlineWidth > 0.0005 {
                    OverlaySwatchRow(model: model, selected: overlay.outlineColor) { color in
                        model.updateSelectedOverlay { $0.outlineColor = color }
                    }
                }
                InspectorSlider(
                    label: "Shadow", value: overlay.shadowOpacity, range: 0...1,
                    valueText: "\(Int(overlay.shadowOpacity * 100))", model: model,
                    set: { newValue in
                        model.updateSelectedOverlay {
                            $0.shadowOpacity = newValue
                            // A shadow with zero blur and zero offset is invisible;
                            // seed sensible geometry the first time it is turned up.
                            if newValue > 0.001, $0.shadowRadius == 0, $0.shadowOffsetY == 0 {
                                $0.shadowRadius = 0.06
                                $0.shadowOffsetY = 0.03
                            }
                        }
                    },
                    reset: { model.pushUndo(); model.updateSelectedOverlay { $0.shadowOpacity = 0 } }
                )
                if overlay.shadowOpacity > 0.001 {
                    InspectorSlider(
                        label: "Blur", value: overlay.shadowRadius, range: 0...0.2,
                        valueText: String(format: "%.0f", overlay.shadowRadius * 100), model: model,
                        set: { newValue in model.updateSelectedOverlay { $0.shadowRadius = newValue } },
                        reset: { model.pushUndo(); model.updateSelectedOverlay { $0.shadowRadius = 0.06 } }
                    )
                }
            }
        }
    }

    /// In / out animation choosers plus their ramp-length sliders.
    @ViewBuilder
    private func animateParams(_ overlay: PhotoOverlay) -> some View {
        let timed = model.selectedTimedOverlay
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                OverlayAnimationRow(
                    title: "In",
                    selected: timed?.animateIn ?? .none
                ) { kind in
                    model.pushUndo()
                    model.updateSelectedTimedOverlay { $0.animateIn = kind }
                }
                if (timed?.animateIn ?? .none) != .none {
                    InspectorSlider(
                        label: "In time", value: timed?.inDuration ?? 0.4, range: 0.1...2,
                        valueText: String(format: "%.1fs", timed?.inDuration ?? 0.4), model: model,
                        set: { newValue in model.updateSelectedTimedOverlay { $0.inDuration = newValue } },
                        reset: { model.pushUndo(); model.updateSelectedTimedOverlay { $0.inDuration = 0.4 } }
                    )
                }
                OverlayAnimationRow(
                    title: "Out",
                    selected: timed?.animateOut ?? .none
                ) { kind in
                    model.pushUndo()
                    model.updateSelectedTimedOverlay { $0.animateOut = kind }
                }
                if (timed?.animateOut ?? .none) != .none {
                    InspectorSlider(
                        label: "Out time", value: timed?.outDuration ?? 0.4, range: 0.1...2,
                        valueText: String(format: "%.1fs", timed?.outDuration ?? 0.4), model: model,
                        set: { newValue in model.updateSelectedTimedOverlay { $0.outDuration = newValue } },
                        reset: { model.pushUndo(); model.updateSelectedTimedOverlay { $0.outDuration = 0.4 } }
                    )
                }
            }
            .padding(.top, 4)
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
        if let music = model.selectedMusicTrack {
            VStack(spacing: 0) {
                InspectorSlider(
                    label: "Volume", value: music.volume, range: 0...1,
                    valueText: "\(Int(music.volume * 100))", model: model,
                    set: { model.setMusicVolume($0, for: music.id) },
                    reset: { model.pushUndo(); model.setMusicVolume(1, for: music.id) }
                )
                InspectorSlider(
                    label: "Fade in", value: music.fadeIn, range: MusicTrack.fadeRange,
                    valueText: String(format: "%.1fs", music.fadeIn), model: model,
                    set: { model.setMusicFadeIn($0, for: music.id) },
                    reset: { model.pushUndo(); model.setMusicFadeIn(2, for: music.id) }
                )
                InspectorSlider(
                    label: "Fade out", value: music.fadeOut, range: MusicTrack.fadeRange,
                    valueText: String(format: "%.1fs", music.fadeOut), model: model,
                    set: { model.setMusicFadeOut($0, for: music.id) },
                    reset: { model.pushUndo(); model.setMusicFadeOut(2, for: music.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var globalParams: some View {
        switch model.activeGlobalTool {
        // No tool open and nothing selected: the inspector has nothing to
        // say, and the screen does not draw it at all. It used to fall
        // through to the ratio strip, which made a 320pt column out of one
        // control that the tool rail already opens by name.
        case .none:
            EmptyView()
        case .ratio:
            VStack(spacing: 0) {
                RatioStrip(model: model).frame(height: 34)
                Spacer(minLength: 0)
            }
        case .color:
            VideoColorPanel(model: model, usesTallScopes: layout == .column)
        case .masterVolume:
            VStack(spacing: 0) {
                // The meter the desk window keeps beside the frame. A fader
                // with nothing to read against it is a guess.
                VideoLevelMeterBar(model: model)
                InspectorSlider(
                    label: "Master", value: model.recipe.masterVolume, range: 0...1,
                    valueText: "\(Int(model.recipe.masterVolume * 100))", model: model,
                    set: { model.setMasterVolume($0) },
                    reset: { model.pushUndo(); model.setMasterVolume(1) }
                )
                InspectorSlider(
                    label: "Clips", value: model.recipe.videoVolume, range: 0...1,
                    valueText: "\(Int(model.recipe.videoVolume * 100))", model: model,
                    set: { model.setVideoVolume($0) },
                    reset: { model.pushUndo(); model.setVideoVolume(1) }
                )
                Spacer(minLength: 0)
            }
        case .background:
            VStack(spacing: 0) {
                BackgroundStrip(model: model).frame(height: 34)
                Spacer(minLength: 0)
            }
        case .filters:
            VStack(spacing: 0) {
                FilterStrip(model: model).frame(height: VideoStudioMetrics.filterStripHeight)
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
        case .adjustments:
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach([PhotoAdjustmentKind.exposure, .contrast, .saturation, .warmth, .brightness, .vignette], id: \.self) { kind in
                        let value = model.activeNode.adjustments[kind]
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
        case .none: []
        }
    }

    private var clipCommands: [VideoCommand] {
        guard let clip = model.selectedClip else { return [] }
        var list: [VideoCommand] = [
            VideoCommand(title: "Split", systemImage: "scissors") { model.splitClipUnderPlayhead() },
        ]
        if clip.kind == .video {
            list.append(VideoCommand(
                title: clip.isMuted ? "Unmute" : "Mute",
                systemImage: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2"
            ) { model.pushUndo(); model.setMuted(!clip.isMuted, for: clip.id) })
        }
        if clip.kind == .video {
            // Stills pick their effect from the chip row in the param zone; a video
            // clip's zone is full (Duration / Speed / Volume), so it keeps the cycle.
            list.append(VideoCommand(title: "Animate", systemImage: "wand.and.stars") { cycleEffect(clip) })
        }
        list.append(VideoCommand(title: "Replace", systemImage: "arrow.triangle.2.circlepath", action: actions.onReplaceClip))
        if clip.kind != .photo {
            list.append(VideoCommand(title: "Freeze", systemImage: "snowflake") { model.freezeUnderPlayhead() })
        }
        if model.mode == .singleVideo {
            list.append(VideoCommand(title: "Rotate", systemImage: "rotate.right") { model.pushUndo(); model.rotateClockwise() })
        }
        // No Delete here: the title row's trash is the one delete for every target.
        return list
    }

    /// Cycle the clip's motion effect (Animate → next VideoClipEffect). A menu
    /// would need another sheet on top of this one; cycling keeps it inline.
    private func cycleEffect(_ clip: VideoClip) {
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
                VideoCommand(title: "Animate", systemImage: "wand.and.stars", tint: model.inspectorTextTool == .animate ? .accent : .normal) {
                    model.inspectorTextTool = model.inspectorTextTool == .animate ? .transform : .animate
                },
                VideoCommand(title: "Copy", systemImage: "plus.square.on.square") { model.duplicateSelectedOverlay() },
            ]
        }
        return [
            // No Edit command: the text field is the first row of the Transform
            // panel, and Bold/Italic live inside Font where they belong.
            textToolCommand("Font", "textformat.alt", .font),
            textToolCommand("Color", "paintpalette", .color),
            textToolCommand("Align", "text.aligncenter", .align),
            textToolCommand("Style", "a.square", .style),
            textToolCommand("Animate", "wand.and.stars", .animate),
            VideoCommand(title: "Copy", systemImage: "plus.square.on.square") { model.duplicateSelectedOverlay() },
        ]
    }

    /// A text sub-tool switch: tint accent while its panel is showing, and tapping
    /// it again returns to the transform panel.
    private func textToolCommand(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        _ tool: VideoStudioModel.TextTool
    ) -> VideoCommand {
        VideoCommand(
            title: title,
            systemImage: systemImage,
            tint: model.inspectorTextTool == tool ? .accent : .normal
        ) {
            model.inspectorTextTool = model.inspectorTextTool == tool ? .transform : tool
        }
    }

    private var musicCommands: [VideoCommand] {
        guard let music = model.selectedMusicTrack else { return [] }
        return [
            VideoCommand(title: "Replace", systemImage: "arrow.triangle.2.circlepath") { actions.onReplaceMusic(music.id) },
            VideoCommand(title: "Add Track", systemImage: "plus", action: actions.onAddMusic),
        ]
    }
}
