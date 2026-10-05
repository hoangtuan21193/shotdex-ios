import SwiftUI
import ShotDexKit

/// A multi-select group's controls under its command row (FS-12.11 §5,
/// boards F1_P_MultiSelect, F1_IL_MultiSelect, F1_DI_Reorder): Speed ·
/// Volume · Fade · Look · Motion, the section a lit command names first.
/// Every control writes every clip it applies to, as one undo step.
struct VideoGroupPanel: View {
    @Bindable var model: VideoStudioModel
    /// The iPad's inspector and dock: Title Case section titles, 36pt
    /// segmented chips.
    var isDesk = false
    /// A column (the iPad's inspector, the Duo's 264): Look is a row of
    /// tiles. The phone's panel has no height for them: Look is a row that
    /// opens the look block (board F1_P_MultiSelect).
    var showsLookTiles = false

    /// Every board puts the section titles and the line under Speed 16 in.
    private let inset: CGFloat = 16
    /// Where the chips start, as the boards draw them: under the iPad's
    /// slider track — the shared slider's 14pt margin, label column and gap
    /// (`EditorValueSlider`), 1126 against the board's 1129 — and at 88 on
    /// the phone (F1_P), 82 in the Duo's 264 column (F1_DI), where the
    /// shared slider's longer label column would leave the chips no room.
    /// The Duo's 264 column: smaller chips (board F1_DI_Reorder).
    private var isColumn: Bool { !isDesk && showsLookTiles }

    private var chipLead: CGFloat {
        if isDesk { return 14 + EditorLayoutMetrics.editorRowLabelWidth + AppTheme.Spacing.sm }
        return showsLookTiles ? 82 : 88
    }

    var body: some View {
        let summary = model.groupSummary
        VStack(alignment: .leading, spacing: 4) {
            ForEach(VideoGroupPanelSections.sections(hasVideo: summary.hasVideo, leading: model.activeItemCommand), id: \.self) { section in
                switch section {
                case .speed: speedSection(summary)
                case .volume: volumeSection
                case .fade: fadeSection
                case .look:
                    if showsLookTiles { lookTiles } else { lookRow }
                case .motion: motionSection
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Speed

    private func speedSection(_ summary: VideoClipGroupEditing.Summary) -> some View {
        let common = model.groupSpeed
        // The phone's and the Duo's chips sit right under the slider's row;
        // the iPad's well 2 below it (F1_P, F1_DI, F1_IL).
        return VStack(alignment: .leading, spacing: isDesk ? 2 : 0) {
            InspectorSlider(
                label: String(localized: "Speed", table: VideoStudioCopy.table, comment: "Video Studio clip panel: label of the playback-rate chips"),
                value: common ?? 1,
                range: VideoClip.speedRange,
                valueText: common.map(Self.speedText) ?? VideoStudioCopy.mixed,
                model: model,
                set: { model.setGroupSpeed($0) },
                reset: { model.chooseGroupSpeed(1) }
            )
            speedChips(common)
            .padding(.leading, chipLead)
            if let note = VideoStudioCopy.speedNote(
                videos: summary.videos,
                stills: VideoClipGroupEditing.stillsSpeedLeaves(model.selectedClipIDs, in: model.recipe)
            ) {
                Text(note)
                    .font(.system(size: isDesk ? 13 : 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
                    .padding(.horizontal, inset)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Volume

    /// Only the clips with sound: the speaker mutes the whole group, and a
    /// mix of muted and not draws it on (FS-12.11 §5).
    @ViewBuilder
    private var volumeSection: some View {
        if isDesk {
            sectionHeader(Text("Audio", tableName: VideoStudioCopy.table, comment: "Video Studio iPad clip panel: header over the clips' volume"))
        }
        MutableVolumeRow(
            isMuted: model.isGroupMuted, volume: model.groupVolume, model: model,
            toggleMute: { model.toggleGroupMuted() },
            set: { model.setGroupVolume($0) },
            reset: { model.pushUndo(); model.setGroupVolume(1) }
        )
    }

    // MARK: Fade

    private var fadeSection: some View {
        let top = max(0.1, VideoClipGroupEditing.maximumFade(model.selectedClipIDs, in: model.recipe))
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(Text("Fade", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: header over the clip's fade in and fade out"))
            ForEach([VideoStudioModel.ClipEnd.start, .end], id: \.self) { end in
                let common = model.groupFade(at: end)
                InspectorSlider(
                    label: Self.fadeLabel(end, isDesk: isDesk),
                    value: common ?? 0, range: 0...top,
                    valueText: common.map { String(format: "%.1fs", $0) } ?? VideoStudioCopy.mixed,
                    model: model,
                    set: { model.setGroupFade($0, at: end) },
                    reset: { model.pushUndo(); model.setGroupFade(0, at: end) }
                )
            }
        }
    }

    // MARK: Look and Motion

    /// "Look · Moody Coast ›" — or Whole video, or Mixed. The row opens
    /// the clip's look block, writing every clip of the group (06c's
    /// Selected), as the Look command does.
    private var lookRow: some View {
        Button {
            model.toggleItemSection(.look)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: VideoItemCommand.look.systemImage)
                    .font(.system(size: isDesk ? 17 : 14, weight: .regular))
                    .frame(width: 26)
                Text(VideoStudioCopy.look)
                    .font(.system(size: isDesk ? 17 : 13.5, weight: .medium))
                Spacer(minLength: 8)
                Text(model.groupLookName)
                    .font(.system(size: isDesk ? 15 : 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, inset)
            .frame(height: isDesk ? 44 : 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The iPad's and the Duo's Look: a header over one row of the shelf's
    /// tiles — 76×68 in the inspector, 46 in the Duo's column — each writing
    /// every clip of the group.
    @ViewBuilder
    private var lookTiles: some View {
        sectionHeader(Text("Look", tableName: VideoStudioCopy.table, comment: "Video Studio multi-select: header over the look tiles that apply to every selected clip"))
        VideoLookPanel(model: model, mode: .groupRow)
            .environment(\.videoLookPanelStyle, groupTileStyle)
    }

    private var groupTileStyle: VideoLookPanelStyle {
        var style = isDesk ? VideoLookPanelStyle.iPad : VideoLookPanelStyle.duoInner
        style.tile = isDesk ? CGSize(width: 76, height: 50) : CGSize(width: 46, height: 46)
        style.columns = nil
        style.fillsColumns = false
        style.tileGap = 8
        style.tileLabelSize = isDesk ? 13 : 10
        style.inset = inset
        return style
    }

    @ViewBuilder
    private var motionSection: some View {
        if isDesk {
            sectionHeader(Text("Motion", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: header over the clip's motion effects — zoom, pan, shake"))
            VideoPopUpButton(
                title: VideoStudioCopy.motion,
                options: VideoClipPanelSections.motionOptions,
                selected: model.groupEffect ?? .none,
                name: \.displayName
            ) { model.setGroupEffect($0) }
            .padding(.horizontal, inset)
        } else {
            ClipEffectRow(selected: model.groupEffect) { model.setGroupEffect($0) }
                .padding(.top, 4)
        }
    }

    /// "In" / "Out" under the phone's FADE; "Fade in" / "Fade out" in the
    /// iPad's inspector (board F1_IL_MultiSelect).
    private static func fadeLabel(_ end: VideoStudioModel.ClipEnd, isDesk: Bool) -> String {
        switch (end, isDesk) {
        case (.start, false): String(localized: "In", table: VideoStudioCopy.table, comment: "Video Studio clip panel: the fade-in slider under FADE")
        case (.end, false): String(localized: "Out", table: VideoStudioCopy.table, comment: "Video Studio clip panel: the fade-out slider under FADE")
        case (.start, true): String(localized: "Fade in", table: VideoStudioCopy.table, comment: "Video Studio iPad clip panel: the fade-in slider")
        case (.end, true): String(localized: "Fade out", table: VideoStudioCopy.table, comment: "Video Studio iPad clip panel: the fade-out slider")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: Text) -> some View {
        if isDesk {
            text
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: VideoStudioMetrics.deskSectionTitleHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .padding(.top, 8)
        } else {
            text
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
                .textCase(.uppercase)
                .padding(.horizontal, inset)
                .padding(.top, 6)
        }
    }

    /// 0.5× · 1× · 2× · 4×: content-sized chips 28 tall on the phone and
    /// the Duo; on the iPad a segmented control, four 56×32 segments in a
    /// 232×36 well (board F1_IL_MultiSelect).
    @ViewBuilder
    private func speedChips(_ common: Double?) -> some View {
        let presets = VideoClipPanelSections.speedPresets
        if isDesk {
            HStack(spacing: 2) {
                ForEach(presets, id: \.self) { speed in
                    chip(speed, isOn: common.map { abs($0 - speed) < 0.001 } ?? false)
                        .frame(width: 56, height: 32)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
        } else {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { speed in
                    chip(speed, isOn: common.map { abs($0 - speed) < 0.001 } ?? false)
                }
            }
            .fixedSize()
        }
    }

    private func chip(_ speed: Double, isOn: Bool) -> some View {
        Button {
            model.chooseGroupSpeed(speed)
        } label: {
            Text(Self.speedText(speed))
                .font(.system(size: isDesk ? 15 : (isColumn ? 11 : 12), weight: .semibold).monospacedDigit())
                .foregroundStyle(isOn ? Color.black : Color.white)
                .padding(.horizontal, isDesk ? 0 : (isColumn ? 10 : 12))
                .frame(minWidth: isDesk ? nil : (isColumn ? 28 : 34), maxWidth: isDesk ? .infinity : nil, maxHeight: isDesk ? .infinity : nil)
                .frame(height: isDesk ? nil : 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.white : (isDesk ? Color.clear : Color.white.opacity(0.08)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static func speedText(_ speed: Double) -> String {
        speed.formatted(.number.precision(.significantDigits(1...2))) + "×"
    }
}

/// The group panel's sections, in order, with a lit command's brought to
/// the top — as `VideoClipPanelSections` orders a single clip's.
enum VideoGroupPanelSection: Equatable, CaseIterable {
    case speed, volume, fade, look, motion
}

enum VideoGroupPanelSections {
    static func sections(hasVideo: Bool, leading command: VideoItemCommand?) -> [VideoGroupPanelSection] {
        let all = VideoGroupPanelSection.allCases.filter { section in
            switch section {
            case .speed, .volume: hasVideo
            case .fade, .look, .motion: true
            }
        }
        let lead: VideoGroupPanelSection? = switch command {
        case .speed: .speed
        case .volume: .volume
        case .motion: .motion
        default: nil
        }
        guard let lead, all.contains(lead) else { return all }
        return [lead] + all.filter { $0 != lead }
    }
}
