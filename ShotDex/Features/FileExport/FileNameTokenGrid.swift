import SwiftUI

/// The eight token chips under a custom name template, three to a row
/// (board `PH34_FileName`). Export's File Name screen and the card import
/// inspector both show this grid, from `FileNameChip.all` (FS-20 AC-25).
struct FileNameTokenGrid: View {
    let onInsert: (FileNameChip) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: 3),
                  spacing: AppTheme.Spacing.sm) {
            ForEach(FileNameChip.all, id: \.self) { chip in
                Button {
                    onInsert(chip)
                } label: {
                    Label(ExportCopy.chipTitle(chip), systemImage: "plus")
                        .labelStyle(TokenChipLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: FileNameMetrics.chipHeight)
                        // Neutral, the look of `.bordered` + `.tint(.secondary)`
                        // without its 12pt side padding (three to a row
                        // wraps "Original Name" otherwise): the sheet's one
                        // accent button is its action (DESIGN.md §3.1).
                        .background(Color(.secondarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(ExportCopy.insertChip(chip))
            }
        }
    }
}

/// `+ Date` on one line, or two when the column is narrow.
private struct TokenChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            configuration.icon.font(.caption.weight(.semibold))
            configuration.title.font(.subheadline).lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }
}

/// From `PH34_FileName`: chips 32pt tall, three to a row.
enum FileNameMetrics {
    static let chipHeight: CGFloat = AppTheme.Size.pillHeightLight
}
