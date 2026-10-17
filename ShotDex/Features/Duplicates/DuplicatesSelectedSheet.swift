import SwiftUI

/// "37 Selected" (FS-06.06b §3): every photo the Delete button would send,
/// group by group with the photo each group keeps, a ring to take a mark
/// back, and the same Delete at the foot — the number on the red pill, here
/// and in the system's dialog is always the same.
struct DuplicatesSelectedSheet: View {
    let model: DuplicatesModel
    @Environment(\.dismiss) private var dismiss

    private let tile: CGFloat = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    ForEach(model.groupsWithMarks) { group in
                        section(group)
                    }
                }
                .padding(AppTheme.Size.screenMargin)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(String(localized: "\(model.markedCount) Selected", comment: "Duplicates: sheet listing the photos marked for deletion"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Close the Selected sheet")) { dismiss() }
                }
            }
            .onChange(of: model.markedCount) { _, count in
                if count == 0 { dismiss() }
            }
        }
    }

    private func section(_ group: DuplicateGroup) -> some View {
        let marked = group.members.filter { model.isMarked($0.assetId) }
        let keeper = model.keeper(of: group)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let keeper {
                    DuplicateThumbnail(asset: model.assetsById[keeper.assetId], side: 32, radius: AppTheme.Radius.sm,
                                       isMarked: false, showsKeep: false, showsMarkBadge: false)
                        .accessibilityHidden(true)
                }
                Text(group.sourceSet?.title ?? group.kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "keeps \(group.count - marked.count)", comment: "Duplicates Selected sheet: how many photos of this group stay"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tile, maximum: tile), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(Array(marked.enumerated()), id: \.element.id) { index, member in
                    DuplicateThumbnail(
                        asset: model.assetsById[member.assetId], side: tile, radius: AppTheme.Radius.sm,
                        isMarked: true, showsKeep: false,
                        onToggleMark: {
                            withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
                        }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Photo \(index + 1) of \(marked.count), \(group.sourceSet?.title ?? group.kind.title)",
                                               comment: "VoiceOver: a marked photo in the Selected sheet"))
                    .accessibilityAddTraits(.isSelected)
                    .accessibilityAction(named: String(localized: "Don't remove", comment: "VoiceOver action: take the mark away")) {
                        withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        let count = model.markedCount
        return Button(role: .destructive) {
            Task {
                if await model.deleteMarked() { dismiss() }
            }
        } label: {
            Label(String(localized: "Delete \(count)", comment: "Duplicates Selected sheet: delete the marked photos"), systemImage: "trash")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.Radius.md))
        .disabled(count == 0 || model.isBusy)
        .accessibilityLabel(count == 1
            ? String(localized: "Delete 1 photo", comment: "VoiceOver: the Delete button")
            : String(localized: "Delete \(count) photos", comment: "VoiceOver: the Delete button"))
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(.bar)
    }
}
