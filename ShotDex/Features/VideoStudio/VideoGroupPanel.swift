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

    private var inset: CGFloat { isDesk ? 16 : 14 }
    /// Where the chips start: under the slider's track, past its label.
    private var chipLead: CGFloat { isDesk ? 96 : 74 }
    private var chipHeight: CGFloat { isDesk ? 36 : 28 }

    var body: some View {
        let summary = model.groupSummary
        VStack(alignment: .leading, spacing: 4) {
            ForEach(VideoGroupPanelSections.sections(hasVideo: summary.hasVideo, leading: model.activeItemCommand), id: \.self) { section in
                switch section {
                case .speed: speedSection(summary)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Speed

    private func speedSection(_ summary: VideoClipGroupEditing.Summary) -> some View {
        let common = model.groupSpeed
        return VStack(alignment: .leading, spacing: 6) {
            InspectorSlider(
                label: String(localized: "Speed", table: VideoStudioCopy.table, comment: "Video Studio clip panel: label of the playback-rate chips"),
                value: common ?? 1,
                range: VideoClip.speedRange,
                valueText: common.map(Self.speedText) ?? VideoStudioCopy.mixed,
                model: model,
                set: { model.setGroupSpeed($0) },
                reset: { model.chooseGroupSpeed(1) }
            )
            HStack(spacing: 6) {
                ForEach(VideoClipPanelSections.speedPresets, id: \.self) { speed in
                    let isOn = common.map { abs($0 - speed) < 0.001 } ?? false
                    Button {
                        model.chooseGroupSpeed(speed)
                    } label: {
                        Text(Self.speedText(speed))
                            .font(.system(size: isDesk ? 15 : 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isOn ? Color.black : Color.white)
                            .padding(.horizontal, 12)
                            .frame(minWidth: isDesk ? 54 : 34)
                            .frame(height: chipHeight)
                            .background(
                                RoundedRectangle(cornerRadius: isDesk ? 8 : 7, style: .continuous)
                                    .fill(isOn ? Color.white : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
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

    private static func speedText(_ speed: Double) -> String {
        speed.formatted(.number.precision(.significantDigits(1...2))) + "×"
    }
}

/// The group panel's sections, in order, with a lit command's brought to
/// the top — as `VideoClipPanelSections` orders a single clip's.
enum VideoGroupPanelSection: Equatable, CaseIterable {
    case speed
}

enum VideoGroupPanelSections {
    static func sections(hasVideo: Bool, leading command: VideoItemCommand?) -> [VideoGroupPanelSection] {
        let all = VideoGroupPanelSection.allCases.filter { section in
            switch section {
            case .speed: hasVideo
            }
        }
        let lead: VideoGroupPanelSection? = switch command {
        case .speed: .speed
        default: nil
        }
        guard let lead, all.contains(lead) else { return all }
        return [lead] + all.filter { $0 != lead }
    }
}
