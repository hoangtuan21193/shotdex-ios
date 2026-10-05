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
    /// Add Music from Files… in the Music panel.
    var onImportMusic: () -> Void = {}
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
        /// The iPad portrait dock: as wide as the window and 324 tall, so a
        /// clip's controls stand in three columns that are all seen at once
        /// rather than one panel that scrolls (FS-12.03 §3).
        case dock
    }

    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    var layout: Layout = .band
    /// The user's songs, for the Music panel.
    var importedMusic: ImportedMusicStore?
    /// A column that is always there (iPad, Duo inner) shows the whole
    /// video's Look when nothing is selected and no tool is open (FS-12.03
    /// §1): the space is spent on what the whole video most often needs.
    var showsIdleLook = false
    /// Tools offered in the idle Look's title — the iPad portrait dock's
    /// Media · Text · Sticker · Music (FS-12.03 §3).
    var idleTools: [VideoAddTool] = []
    /// The iPad's inspector column, whose content already starts under the
    /// toolbar at 80: the command row sits at its top, 13 in (FS-12.03 §2).
    var isDeskInspector = false

    /// A project of server photos, for Export Video's destination.
    var server: ServerVideoStudioLaunch?
    var onServerExported: () -> Void = {}

    var body: some View {
        Group {
            if model.mediaPickPurpose == .replaceClip {
                // Replace (FS-12.04b §4): Media in single-pick mode, in the
                // clip's own place — the clip's ✕ / ✓ stays.
                VideoMediaPanel(model: model)
            } else if showsIdleLook, model.inspectorTarget == .none, model.activeToolPanel == nil {
                idleLook
            } else if model.inspectorTarget == .none, model.activeToolPanel == .look {
                lookToolPanel
            } else if model.inspectorTarget == .none, model.activeToolPanel == .music, let importedMusic {
                musicPanel(importedMusic)
            } else if model.inspectorTarget == .none, model.activeToolPanel == .media {
                VideoMediaPanel(model: model)
            } else if model.inspectorTarget == .none, model.activeToolPanel == .videoSettings {
                VideoSettingsPanel(model: model)
            } else if model.inspectorTarget == .none, model.activeToolPanel == .export {
                VideoExportPanel(model: model, server: server, onServerExported: onServerExported)
            } else {
                switch layout {
                case .band: bandBody
                case .column, .dock: columnBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorTheme.panelSolid)
        .animation(EditorTheme.animation, value: model.inspectorTarget)
        .animation(EditorTheme.animation, value: model.activeToolPanel)
    }

    /// The Music panel (board P4): a 46pt title — glyph, "Add Music", ✕ —
    /// over Video sound, Add Music from Files… and My Music. The bottom row
    /// keeps its five tools while it is open.
    private func musicPanel(_ importedMusic: ImportedMusicStore) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                Text(VideoStudioCopy.addMusic)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // ✕ throws away everything changed since the panel opened —
                // Video sound included — and leaves no undo step behind
                // (FS-12.04 §4). Closing any other way keeps.
                Button {
                    model.cancelSession()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.discardChanges)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: VideoStudioMetrics.musicPanelTitleHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            VideoMusicPanelContent(model: model, importedMusic: importedMusic, onImport: actions.onImportMusic)
        }
    }

    /// "Look · Whole video" over the Look controls, with no ✕ or ✓: nothing
    /// was opened, so there is no session to end — each change is its own
    /// undo step.
    private var idleLook: some View {
        VStack(spacing: 0) {
            if layout == .dock {
                dockLookTitle
                Color.clear.frame(height: VideoStudioDeskGeometry.dockColumnsTop - VideoStudioDeskGeometry.dockCommandRowTop - VideoStudioDeskGeometry.dockButtonSize.height)
            } else {
                lookTitle(showsSessionButtons: false)
            }
            VideoLookPanel(model: model, usesTallScopes: layout != .band)
        }
    }

    /// The portrait dock's head with nothing selected (FS-12.03 §3, board
    /// IP1_Main): "Look" 20 · "Whole video", and the four ways to add —
    /// Media · Text · Sticker · Music, 104×44, 8 apart — on the right.
    private var dockLookTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(VideoStudioCopy.look)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.lookSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 0)
            HStack(spacing: VideoStudioDeskGeometry.dockButtonGap) {
                ForEach(idleTools) { tool in
                    idleToolButton(tool)
                }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
        }
        .lineLimit(1)
        .padding(.horizontal, VideoStudioDeskGeometry.dockInset)
        .frame(height: VideoStudioDeskGeometry.dockButtonSize.height)
        .padding(.top, VideoStudioDeskGeometry.dockCommandRowTop)
    }

    /// The Look tool's panel (FS-12.06c §3, board F5_P_Looks): a 46pt title
    /// — glyph, "Look", "Whole video", hold-to-compare, ✕, ✓ — over the
    /// panel.
    private var lookToolPanel: some View {
        VStack(spacing: 0) {
            lookTitle(showsSessionButtons: true)
            VideoLookPanel(model: model, usesTallScopes: layout != .band)
        }
    }

    private func lookTitle(showsSessionButtons: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.20))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: VideoToolPanel.look.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            Text(VideoStudioCopy.look)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.lookSubtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
            ForEach(idleTools) { tool in
                idleToolButton(tool)
            }
            if showsSessionButtons {
                beforeAfterButton
                Button {
                    model.cancelSession()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.discardChanges)
                Button {
                    model.commitSession()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(VideoStudioCopy.keepChanges))
            }
        }
        .lineLimit(1)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: VideoStudioMetrics.musicPanelTitleHeight)
    }

    /// One of the dock's add buttons: glyph and name, 104×44, radius 12.
    private func idleToolButton(_ tool: VideoAddTool) -> some View {
        Button {
            switch tool {
            case .media: actions.onAddMedia()
            case .text: actions.onAddText()
            case .sticker: actions.onAddSticker()
            case .music: actions.onAddMusic()
            case .look: break
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 17, weight: .medium))
                Text(tool.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: VideoStudioDeskGeometry.dockButtonSize.width, height: VideoStudioDeskGeometry.dockButtonSize.height)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioDeskGeometry.dockButtonRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bandBody: some View {
        Group {
            if model.inspectorTarget != .none {
                itemBody
            } else {
                VStack(spacing: 0) {
                    titleRow
                        .frame(height: VideoStudioMetrics.sheetTitleHeight)
                        .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
                    paramZone
                        .frame(height: VideoStudioMetrics.sheetParamHeight)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var columnBody: some View {
        Group {
            if model.inspectorTarget != .none {
                itemBody
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        titleRow
                            .frame(minHeight: VideoStudioMetrics.sheetTitleHeight)
                            .padding(.top, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
                        paramZone
                            .padding(.top, 10)
                    }
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// A selected item's panel (FS-12.04b): its command row first — the
    /// same row on every layout, never a grid — a 1pt rule, then its
    /// controls. No title row and no trash: the name is in ✕ · name · ✓
    /// and Delete is the row's last cell.
    private var itemBody: some View {
        VStack(spacing: 0) {
            VideoItemCommandRow(
                commands: model.selectedItemCommands,
                isOn: { model.isItemCommandOn($0) },
                isEnabled: { model.isItemCommandEnabled($0) },
                perform: perform,
                inset: isDeskInspector ? VideoStudioDeskGeometry.inspectorCommandInset : VideoStudioMetrics.itemCommandRowInset
            )
            .padding(.top, isDeskInspector ? 0 : VideoStudioMetrics.itemCommandRowTop)
            if let note = model.itemCommandNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VideoStudioMetrics.itemCommandRowInset)
                    .padding(.top, 2)
            }
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.top, 6)
                .padding(.bottom, 4)
            if model.inspectorTarget == .clip, model.activeItemCommand == .look {
                // Look (FS-12.06c §3): the clip's own look block takes the
                // panel, as Trim's chips take it for a cut.
                VideoLookPanel(model: model, mode: .clip, usesTallScopes: layout != .band)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if layout == .dock, model.inspectorTarget == .clip, let clip = model.selectedClip {
                dockClipColumns(clip)
            } else {
                paramZone
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// A clip's controls in the dock's three columns: Duration · Speed ·
    /// Volume | FADE | MOTION (FS-12.03 §3). Each column is a third of the
    /// dock — 344 on a 1032 window — and 190 tall.
    private func dockClipColumns(_ clip: VideoClip) -> some View {
        let sections = VideoClipPanelSections.sections(for: clip.kind, leading: model.activeItemCommand)
        let columns: [[VideoClipPanelSection]] = [
            sections.filter { $0 != .fade && $0 != .motion },
            sections.filter { $0 == .fade },
            sections.filter { $0 == .motion },
        ]
        return GeometryReader { geo in
            let width = VideoStudioDeskGeometry.dockColumnWidth(width: geo.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                if index == 0, model.activeItemCommand == .trim { trimBlock(clip) }
                                ForEach(column, id: \.self) { section in
                                    clipSection(section, clip)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .frame(width: width, height: VideoStudioDeskGeometry.dockParamHeight, alignment: .top)
                        .overlay(alignment: .trailing) {
                            if index < columns.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
                            }
                        }
                    }
                }
            }
            .scrollDisabled(width * 3 <= geo.size.width + 0.5)
        }
        .frame(height: VideoStudioDeskGeometry.dockParamHeight)
    }

    private func perform(_ command: VideoItemCommand) {
        if command.isSection {
            model.toggleItemSection(command)
            return
        }
        switch command {
        case .split:
            model.splitClipUnderPlayhead()
        case .replace:
            if let id = model.selectedMusicID {
                actions.onReplaceMusic(id)
            } else {
                actions.onReplaceClip()
            }
        case .freeze:
            model.freezeUnderPlayhead()
        case .duplicate:
            switch model.inspectorTarget {
            case .clip: model.duplicateSelectedClip()
            case .text: model.duplicateSelectedOverlay()
            case .music: model.duplicateSelectedMusic()
            case .none: break
            }
        case .rotate:
            model.pushUndo()
            model.rotateClockwise()
        case .addTrack:
            actions.onAddMusic()
        case .delete:
            switch model.inspectorTarget {
            case .clip: if let id = model.selectedClipID { model.deleteClip(id) }
            case .text: model.deleteSelectedOverlay()
            case .music: if let id = model.selectedMusicID { model.removeMusicTrack(id) }
            case .none: break
            }
        default:
            break
        }
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
        case .none: (model.activeToolPanel?.systemImage ?? "slider.horizontal.3", false)
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
        case .none: model.activeToolPanel?.title ?? String(localized: "Project")
        }
    }

    private var subtitleText: String? {
        switch model.inspectorTarget {
        case .clip:
            // "6.2s · video": the length, and what kind of clip it is.
            return model.selectionTitle?.detail
        case .text: return nil
        case .music:
            guard let music = model.selectedMusicTrack else { return nil }
            return String(format: "%.1fs → %.1fs", music.start, music.end)
        case .none: return "\(model.recipe.clips.count) clips · \(model.recipe.aspect.displayName)"
        }
    }

    /// Buttons on a tool panel's title row. An item's panel has no title
    /// row: Delete is the last cell of its command row.
    @ViewBuilder
    private var titleButtons: some View {
        switch model.inspectorTarget {
        case .clip, .text, .music:
            EmptyView()
        case .none:
            switch model.activeToolPanel {
            case .look, .music, .media, .videoSettings, .export, nil: EmptyView()
            }
        }
    }

    /// Press and hold, like the photo editor's before/after: the preview
    /// drops the look — filter, adjustments, grade — and every overlay while
    /// the finger is down. In the Look panel's title, beside what it
    /// compares (FS-12.04 §4).
    private var beforeAfterButton: some View {
        let isEnabled = model.hasEdits
        return Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(
                model.showsOriginal ? Color.black : (isEnabled ? Color.white : Color.white.opacity(0.28))
            )
            .frame(width: VideoStudioMetrics.inspectorTitleButton, height: VideoStudioMetrics.inspectorTitleButton)
            .background(Circle().fill(model.showsOriginal ? Color.white : Color.white.opacity(0.06)))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !model.showsOriginal else { return }
                        model.setShowsOriginal(true)
                    }
                    .onEnded { _ in model.setShowsOriginal(false) }
            )
            .allowsHitTesting(isEnabled)
            .accessibilityElement()
            .accessibilityLabel(Text("Show original", comment: "Video Studio: press-and-hold control that previews the clips without edits"))
            .accessibilityHint(Text("Press and hold to see the clips without edits", comment: "Hint for the Video Studio before/after control"))
            .accessibilityAddTraits(model.showsOriginal ? .isSelected : [])
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

    /// The clip's controls, section by section (`VideoClipPanelSections`):
    /// a video gets Speed · Volume · Fade · Motion, a still Duration · Fade ·
    /// Motion.
    @ViewBuilder
    private var clipParams: some View {
        if let clip = model.selectedClip {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if model.activeItemCommand == .trim { trimBlock(clip) }
                    ForEach(
                        VideoClipPanelSections.sections(for: clip.kind, leading: model.activeItemCommand),
                        id: \.self
                    ) { section in
                        clipSection(section, clip)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func clipSection(_ section: VideoClipPanelSection, _ clip: VideoClip) -> some View {
        switch section {
        case .speed:
            speedChips(clip)
        case .volume:
            // This clip's level, not the project's: Video sound is the
            // Music panel's (FS-12.08 §2). Its speaker mutes it.
            MutableVolumeRow(
                isMuted: clip.isMuted, volume: clip.volume, model: model,
                toggleMute: { model.toggleClipMuted(clip.id) },
                set: { model.setClipVolume($0, for: clip.id) },
                reset: { model.pushUndo(); model.setClipVolume(1, for: clip.id) }
            )
        case .duration:
            durationSlider(clip)
        case .fade:
            sectionHeader(Text("Fade", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: header over the clip's fade in and fade out"))
            InspectorSlider(
                label: "In", value: clip.fadeIn, range: 0...max(0.1, clip.maximumFade()),
                valueText: String(format: "%.1fs", clip.fadeIn), model: model,
                set: { model.setFade($0, at: .start, for: clip.id) },
                reset: { model.pushUndo(); model.setFade(0, at: .start, for: clip.id) }
            )
            InspectorSlider(
                label: "Out", value: clip.fadeOut, range: 0...max(0.1, clip.maximumFade()),
                valueText: String(format: "%.1fs", clip.fadeOut), model: model,
                set: { model.setFade($0, at: .end, for: clip.id) },
                reset: { model.pushUndo(); model.setFade(0, at: .end, for: clip.id) }
            )
        case .motion:
            ClipEffectRow(selected: clip.effect) { effect in
                guard effect != clip.effect else { return }
                model.setEffect(effect, for: clip.id)
            }
            .padding(.top, 4)
        }
    }

    /// Trim's block (FS-12.04b §4, FS-12.05 §3): Start to Playhead · End to
    /// Playhead, and how else a clip is cut.
    private func trimBlock(_ clip: VideoClip) -> some View {
        // With the playhead outside the clip, or on its edge, there is
        // nothing to cut: the chips dim and say where the playhead must go
        // (FS-12.05 AC-7) rather than doing nothing on a tap.
        let isAvailable = model.trimChipsUnavailable == nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                trimChip(VideoStudioCopy.startToPlayhead, systemImage: "arrow.left.to.line", isEnabled: isAvailable) {
                    trim(.start)
                }
                trimChip(VideoStudioCopy.endToPlayhead, systemImage: "arrow.right.to.line", isEnabled: isAvailable) {
                    trim(.end)
                }
            }
            Text(isAvailable ? VideoStudioCopy.dragEdgesHint : VideoStudioCopy.movePlayheadIntoClip)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// One chip's cut. What would be left under a clip's minimum does
    /// nothing, and says so with the error haptic.
    private func trim(_ end: VideoStudioModel.ClipEnd) {
        if model.trimSelectedClipToPlayhead(end) == .tooShort {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func trimChip(_ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.28))
            .frame(maxWidth: .infinity)
            .frame(height: VideoStudioMetrics.trimChipHeight)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trimChipRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func sectionHeader(_ text: Text) -> some View {
        text
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(EditorTheme.dimText)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 6)
    }

    /// 0.5× · 1× · 2× · 4× — the speeds a cut is usually after, one tap each.
    private func speedChips(_ clip: VideoClip) -> some View {
        HStack(spacing: 6) {
            Text("Speed", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: label of the playback-rate chips")
                .font(.system(size: 12))
                .foregroundStyle(EditorTheme.dimText)
                .frame(width: 64, alignment: .leading)
            ForEach(VideoClipPanelSections.speedPresets, id: \.self) { speed in
                let isOn = abs(clip.speed - speed) < 0.001
                Button {
                    guard !isOn else { return }
                    model.pushUndo()
                    model.setSpeed(speed, for: clip.id)
                } label: {
                    Text(speed.formatted(.number.precision(.significantDigits(1...2))) + "×")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isOn ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    /// How long a still stays on screen, 0.5–10 s. Stills only: a video's
    /// length is cut at its edges.
    private func durationSlider(_ clip: VideoClip) -> some View {
        InspectorSlider(
            label: "Duration", value: clip.photoDuration, range: VideoClip.photoDurationRange,
            valueText: String(format: "%.1fs", clip.photoDuration), model: model,
            set: { model.setPhotoDuration($0, for: clip.id) },
            reset: { model.pushUndo(); model.setPhotoDuration(VideoClip.defaultPhotoDuration, for: clip.id) }
        )
    }

    @ViewBuilder
    private var textParams: some View {
        if let overlay = model.selectedOverlay {
            switch model.inspectorTextTool {
            case .edit: transformParams(overlay, editsText: true)
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
    private func transformParams(_ overlay: PhotoOverlay, editsText: Bool = false) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Content first: editing the words is the commonest reason to
                // open a caption, so it never hides behind a command.
                if overlay.kind == .text {
                    OverlayTextField(
                        model: model, overlay: overlay,
                        onExpand: { actions.onEditText(overlay) },
                        focusesOnAppear: editsText
                    )
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
                MutableVolumeRow(
                    isMuted: music.isMuted, volume: music.volume, model: model,
                    toggleMute: { model.toggleMusicMuted(music.id) },
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
        switch model.activeToolPanel {
        // No panel open and nothing selected: the inspector has nothing to
        // say, and the screen does not draw it at all.
        case .none:
            EmptyView()
        case .look, .music, .media, .videoSettings, .export:
            // Drawn by their own panels in place of the whole band.
            EmptyView()
        }
    }

}
