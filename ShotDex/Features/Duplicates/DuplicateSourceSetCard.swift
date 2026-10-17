import SwiftUI

/// A bracket or focus stack (FS-06.06 §7.5, board `PH_DuplicatesLargeGroup`):
/// raw material for a merge, so no keeper, no red button and no share of
/// "~GB to free". Every frame in one grid in capture order, each saying how
/// it was shot differently (−2 EV); the merge, Choose frames for a focus
/// stack, and Not duplicates.
struct DuplicateSourceSetCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.sourceSet?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                if let date = DuplicatesScreen.dateText(group) {
                    Text([date, DuplicateReview.spanText(group.members)].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(metrics.tile), spacing: DuplicateCardMetrics.copyGap),
                               count: metrics.gridColumns),
                alignment: .leading,
                spacing: DuplicateCardMetrics.copyGap
            ) {
                ForEach(group.members) { member in
                    tile(member)
                }
            }

            actions
        }
        .padding(DuplicateCardMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
    }

    private func tile(_ member: HashedPhoto) -> some View {
        let isMarked = model.isMarked(member.assetId)
        return DuplicateThumbnail(
            asset: model.assetsById[member.assetId],
            side: metrics.tile,
            radius: AppTheme.Radius.sm,
            isMarked: isMarked,
            showsKeep: false,
            onToggleMark: {
                withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
            },
            factLines: DuplicateReview.settings(of: member, members: group.members).map { [$0] } ?? []
        )
        .onTapGesture { model.compare(group, from: member.assetId) }
        .sensoryFeedback(.selection, trigger: isMarked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DuplicateReview.settings(of: member, members: group.members) ?? group.sourceSet?.title ?? "")
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.compare(group, from: member.assetId) }
        .accessibilityAction(named: isMarked
                             ? String(localized: "Don't remove", comment: "VoiceOver action on a tile")
                             : String(localized: "Remove", comment: "VoiceOver action on a tile")) {
            _ = model.toggleMark(member.assetId, in: group)
        }
    }

    private var actions: some View {
        let isBracket = group.sourceSet?.kind == .bracket
        return HStack(spacing: AppTheme.Spacing.sm) {
            Button(isBracket
                   ? String(localized: "Merge to HDR", comment: "Duplicates bracket card: open the HDR merge on these frames")
                   : String(localized: "Focus Stack", comment: "Duplicates focus-stack card: open Focus Stack on these frames")) {
                model.merge(group)
            }
            .buttonStyle(.bordered)
            if !isBracket, let first = group.members.first {
                Button(String(localized: "Choose frames", comment: "Duplicates card: pick which frames of the run to keep")) {
                    model.openFrames(group, at: first.assetId)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Not duplicates", comment: "Duplicates card: these photos are not duplicates; never show them again")) {
                withAnimation(AppTheme.Motion.standard) { model.dismiss(group) }
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .controlSize(.regular)
        .frame(minHeight: 44)
        .disabled(model.isBusy)
    }
}
