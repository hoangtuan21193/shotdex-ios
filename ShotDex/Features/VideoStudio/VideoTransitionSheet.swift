import SwiftUI

/// Picking what happens at one cut, and how long it takes.
///
/// It replaces a `confirmationDialog`, for two reasons. The duration was the
/// one transition control the maths already supported and nothing exposed —
/// `VideoBoundaryTransition.duration` had a `durationRange` and a default and
/// no way for anyone to change it. And a `confirmationDialog` cannot hold a
/// slider; on iOS 26 it also draws as a popover that hides the `.cancel`
/// button, which is why the rest of tier D stopped using it (spec §10.5).
struct VideoTransitionSheet: View {
    @Bindable var model: VideoStudioModel
    let index: Int
    let onClose: () -> Void

    private var transition: VideoBoundaryTransition {
        model.recipe.transitions.indices.contains(index)
            ? model.recipe.transitions[index]
            : VideoBoundaryTransition()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transition", comment: "Video Studio: title of the sheet that edits one cut")
                    .font(EditorTheme.panelTitle)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    model.pushUndo()
                    model.setAllTransitions(transition)
                    onClose()
                } label: {
                    Text("Apply to All", comment: "Video Studio: puts this transition on every cut in the project")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.recipe.transitions.count < 2)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VideoTransitionKind.allCases) { kind in
                        kindCell(kind)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }

            // Only where it can do anything: a cut with no transition has no
            // length to set.
            if transition.kind != .none {
                InspectorSlider(
                    label: "Duration",
                    value: transition.duration,
                    range: VideoBoundaryTransition.durationRange,
                    valueText: String(format: "%.1fs", transition.duration),
                    model: model,
                    set: { seconds in
                        model.setTransition(
                            VideoBoundaryTransition(kind: transition.kind, duration: seconds),
                            at: index
                        )
                    },
                    reset: {
                        model.pushUndo()
                        model.setTransition(
                            VideoBoundaryTransition(kind: transition.kind, duration: 0.5),
                            at: index
                        )
                    }
                )
                .padding(.top, AppTheme.Spacing.sm)
                // What the timeline math will actually allow: a transition
                // can never eat more than half of the shorter neighbour, so a
                // slider that promises 2s on a 0.6s clip is a slider that
                // lies.
                Text(allowanceNote)
                    .font(.system(size: 11))
                    .foregroundStyle(EditorTheme.dimText)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorTheme.panelSolid)
        .preferredColorScheme(.dark)
    }

    /// Split out of the row: the whole `ScrollView` with this inline is past
    /// what the type checker will solve in time.
    private func kindCell(_ kind: VideoTransitionKind) -> some View {
        let isOn = kind == transition.kind
        return Button { apply(kind: kind) } label: {
            VStack(spacing: 4) {
                Text(kind.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Color.black : Color.white)
            .frame(width: 74, height: 56)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                    .fill(isOn ? EditorTheme.accent : EditorTheme.trackChip)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func apply(kind: VideoTransitionKind) {
        model.pushUndo()
        model.setTransition(
            VideoBoundaryTransition(kind: kind, duration: transition.duration),
            at: index
        )
    }

    private var allowanceNote: String {
        let effective = VideoTimelineMath.effectiveOverlaps(
            requested: model.recipe.transitions.map(\.requestedOverlap),
            durations: model.clipPlacements.map(\.duration)
        )
        let granted = effective.indices.contains(index) ? effective[index] : 0
        guard granted + 0.01 < transition.duration else {
            return String(
                localized: "Both clips are long enough for this.",
                comment: "Video Studio transition sheet: the requested length fits"
            )
        }
        return String(
            localized: "Shortened to \(String(format: "%.1f", granted))s — a transition can take at most half of the shorter clip.",
            comment: "Video Studio transition sheet: the timeline had to clamp the requested length"
        )
    }
}
