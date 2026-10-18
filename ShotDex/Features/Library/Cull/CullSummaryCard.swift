import SwiftUI

/// The card at the end of the pass (FS-01.12b §2, board `PH24`): what the
/// pass decided, and the three ways on — Move / Delete / Hide N Rejected…
/// (red, named after where they go), Review Unflagged, Done.
struct CullSummaryCard: View {
    let summary: CullSummary
    var deleteTitle: String? = nil
    /// Nil where the pass cannot delete (nothing hosts the deletion).
    let onDeleteRejected: (() -> Void)?
    let onReviewUnflagged: () -> Void
    let onDone: () -> Void

    static let width: CGFloat = 370
    static let buttonHeight: CGFloat = 50

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Image(systemName: PhotoCommand.cull.systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
                    .accessibilityHidden(true)
                Text(MarkCopy.endOfSet)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
                Text(MarkCopy.cullSummary(summary))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                VStack(spacing: 8) {
                    // A row that would act on nothing is left out rather
                    // than shown dead: no Rejected, no Delete; nothing
                    // unflagged, no Review.
                    if summary.rejected > 0, let onDeleteRejected {
                        cardButton(deleteTitle ?? MarkCopy.deleteRejected(summary.rejected), systemImage: "trash",
                                   foreground: EditorTheme.timelineDestructive,
                                   background: Color.red.opacity(0.16), action: onDeleteRejected)
                    }
                    if summary.unflagged > 0 {
                        cardButton(MarkCopy.reviewUnflagged, foreground: .white,
                                   background: EditorTheme.control, action: onReviewUnflagged)
                    }
                    cardButton(MarkCopy.done, foreground: .black, background: EditorTheme.accent, action: onDone)
                }
                .padding(.top, 22)
            }
            .padding(EdgeInsets(top: 22, leading: 18, bottom: 18, trailing: 18))
            .frame(maxWidth: Self.width)
            .background(EditorTheme.panelSolid, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(EditorTheme.panelTopHairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
            .padding(.horizontal, CullLayout.edgeInset)
            .accessibilityElement(children: .contain)
        }
    }

    private func cardButton(
        _ title: String, systemImage: String? = nil,
        foreground: Color, background: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
