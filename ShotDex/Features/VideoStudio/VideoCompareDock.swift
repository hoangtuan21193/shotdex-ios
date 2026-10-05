import SwiftUI
import ShotDexKit

/// The iPad portrait dock while Before and After is on and nothing is
/// selected (FS-12.15 §4, board F7_IP): "Before and After · Clip 2" over
/// three columns of 312 — Look (the look and its Amount), Compare (Side by
/// Side · Split, Swap Sides, what Before shows) and Adjust.
struct VideoCompareDock: View {
    @Bindable var model: VideoStudioModel

    private var clipName: String {
        guard let index = model.clipIndexUnderPlayhead, index < model.recipe.clips.count else { return VideoStudioCopy.wholeVideo }
        return VideoItemTitle.clipName(model.recipe.clips[index].kind, index: index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(VideoStudioCopy.beforeAndAfter)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: clipName)
                    .font(.system(size: 15))
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.horizontal, VideoStudioDeskGeometry.dockInset)
            .frame(height: VideoStudioDeskGeometry.dockButtonSize.height)
            .padding(.top, VideoStudioDeskGeometry.dockCommandRowTop)
            Color.clear.frame(height: VideoStudioDeskGeometry.dockColumnsTop - VideoStudioDeskGeometry.dockCommandRowTop - VideoStudioDeskGeometry.dockButtonSize.height)
            DockColumns(gap: VideoStudioDeskGeometry.dockColumnGap) {
                lookColumn
            } second: {
                compareColumn
            } third: {
                adjustColumn
            }
            .frame(height: VideoStudioDeskGeometry.dockParamHeight)
            .padding(.horizontal, VideoStudioDeskGeometry.dockInset)
        }
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 24, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var lookColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(VideoStudioCopy.look)
            if let look = model.lookSlot {
                Text(verbatim: VideoLookEditing.name(of: look, presetName: model.presetName))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 44, alignment: .leading)
                if VideoLookEditing.showsAmount(look) {
                    DeskSliderRow(
                        label: VideoStudioCopy.lookAmount, value: look.amount, range: 0...1,
                        valueText: "\(Int((look.amount * 100).rounded()))", model: model,
                        set: { model.setLookAmount($0) },
                        reset: { model.pushUndo(); model.setLookAmount(1) }
                    )
                }
            } else {
                Text(VideoStudioCopy.noEditsToCompare)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var compareColumn: some View {
        if let compare = model.compare {
            VStack(alignment: .leading, spacing: 8) {
                title(VideoStudioCopy.compareTitle)
                VideoDeskSegmented(
                    items: VideoBeforeAfter.modes(sideBySide: true).map { ($0, VideoStudioCopy.compareMode($0), "compareMode.\($0.rawValue)") },
                    selection: Binding(get: { compare.mode }, set: { model.setCompareMode($0) }),
                    label: Text(VideoStudioCopy.compareTitle)
                )
                Button {
                    model.swapCompareSides()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 15, weight: .medium))
                        Text(VideoStudioCopy.swapSides)
                            .font(.system(size: 17))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .foregroundStyle(.white)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(compare.mode != .sideBySide)
                .opacity(compare.mode == .sideBySide ? 1 : 0.35)
                .accessibilityAddTraits(compare.isSwapped ? .isSelected : [])
                .accessibilityIdentifier("compareSwapSides")
                HStack(spacing: 10) {
                    Image(systemName: "eye")
                        .font(.system(size: 15, weight: .medium))
                    Text(VideoStudioCopy.beforeShows)
                        .font(.system(size: 17))
                    Spacer(minLength: 0)
                    Text(VideoStudioCopy.originalClip)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .foregroundStyle(.white)
                .frame(height: 44)
                .accessibilityElement(children: .combine)
                Text(model.hasNothingToCompare ? VideoStudioCopy.noEditsToCompare : VideoStudioCopy.beforeDropsNote)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var adjustColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(VideoStudioCopy.adjustTitle).padding(.bottom, 4)
            ForEach([PhotoAdjustmentKind.exposure, .contrast, .saturation, .warmth], id: \.self) { kind in
                let value = model.activeNode.adjustments[kind]
                DeskSliderRow(
                    label: kind.displayName, value: value, range: -1...1,
                    valueText: String(format: "%+.0f", value * 100), anchor: 0, model: model,
                    set: { model.setAdjustment(kind, value: $0) },
                    reset: { model.pushUndo(); model.setAdjustment(kind, value: 0) }
                )
            }
            Spacer(minLength: 0)
        }
    }
}
