import SwiftUI

/// Floating glass tray shown during multi-select: selection count plus the
/// available actions — optional Compare (enabled for 2–4 photos) and Delete.
struct SelectionActionsTray: View {
    let selectionCount: Int
    /// nil hides the Compare button (e.g. On This Day is delete-only).
    let onCompare: (() -> Void)?
    let onDelete: () -> Void
    let isDeleting: Bool

    private var compareRange: ClosedRange<Int> { 2...CompareScreen.maxPhotoCount }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                if onCompare != nil, !compareRange.contains(selectionCount) {
                    Text("Select 2–\(CompareScreen.maxPhotoCount) photos to compare")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text("\(selectionCount) selected")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Spacer()
                    if let onCompare {
                        Button("Compare", action: onCompare)
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .disabled(!compareRange.contains(selectionCount))
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(selectionCount == 0 || isDeleting)
                }
            }
            .padding(14)
            .animation(.snappy(duration: 0.2), value: selectionCount)
        }
    }
}

/// Checkmark badge on a grid tile during multi-select.
struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .background(Circle().fill(isSelected ? .white : .black.opacity(0.35)))
            .padding(6)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack(spacing: 16) {
            SelectionActionsTray(selectionCount: 1, onCompare: {}, onDelete: {}, isDeleting: false)
            SelectionActionsTray(selectionCount: 3, onCompare: {}, onDelete: {}, isDeleting: false)
            SelectionActionsTray(selectionCount: 12, onCompare: nil, onDelete: {}, isDeleting: false)
        }
        .padding(.horizontal)
    }
}
