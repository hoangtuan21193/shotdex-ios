import SwiftUI

/// A bracket or focus stack (FS-06.06 §7.5): raw material for a merge, so no
/// keeper and no share of "~GB to free". Shown under Burst, and like every
/// card only photos (2026-10-21): every frame in one grid in capture order,
/// each saying how it was shot differently (−2 EV). A tap opens Choose
/// frames; a hold offers the merge and Not duplicates.
struct DuplicateSourceSetCard: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    let metrics: DuplicateCardMetrics

    var body: some View {
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
        .padding(DuplicateCardMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.sourceSet?.title ?? "")
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
                withAnimation(AppTheme.Motion.standard) { model.toggleMark(member.assetId, in: group) }
            },
            factLines: DuplicateReview.settings(of: member, members: group.members).map { [$0] } ?? []
        )
        .onTapGesture { model.openFrames(group, at: member.assetId) }
        .sensoryFeedback(.selection, trigger: isMarked)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DuplicateReview.settings(of: member, members: group.members) ?? group.sourceSet?.title ?? "")
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.openFrames(group, at: member.assetId) }
        .accessibilityAction(named: isMarked
                             ? String(localized: "Don't remove", comment: "VoiceOver action on a tile")
                             : String(localized: "Remove", comment: "VoiceOver action on a tile")) {
            model.toggleMark(member.assetId, in: group)
        }
    }

    /// The merge and Not duplicates left the card's button row for the
    /// hold menu (2026-10-21).
    @ViewBuilder
    private var menu: some View {
        let isBracket = group.sourceSet?.kind == .bracket
        Button {
            model.merge(group)
        } label: {
            Label(isBracket
                  ? String(localized: "Merge to HDR", comment: "Duplicates bracket card: open the HDR merge on these frames")
                  : String(localized: "Focus Stack", comment: "Duplicates focus-stack card: open Focus Stack on these frames"),
                  systemImage: isBracket ? "camera.aperture" : "square.stack.3d.down.right")
        }
        .disabled(model.isDeleting)
        Button {
            withAnimation(AppTheme.Motion.standard) { model.dismiss(group) }
        } label: {
            Label(String(localized: "Not duplicates", comment: "Duplicates card: these photos are not duplicates; never show them again"),
                  systemImage: "eye.slash")
        }
        .disabled(model.isDeleting)
    }
}
