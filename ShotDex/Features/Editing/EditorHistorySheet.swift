import SwiftUI

/// Every recorded step of the session, newest first, with what it changed and how
/// far back it is. Tapping a row jumps the session to that state; the labels are
/// derived by diffing neighbouring recipes rather than being recorded up front.
struct EditorHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: PhotoEditorController

    private struct Step: Identifiable {
        let id: Int
        let label: String
        let distance: String
    }

    private var steps: [Step] {
        let timeline = controller.historyTimeline
        let current = controller.historyCurrentIndex
        return timeline.indices.reversed().map { index in
            let label: String = if index == 0 {
                timeline[index].isIdentity ? "Original" : "Opened with saved edit"
            } else {
                EditorAdjustmentSummary.describeChange(
                    from: timeline[index - 1],
                    to: timeline[index]
                )
            }
            let distance: String = if index == current {
                "now"
            } else if index < current {
                "−\(current - index)"
            } else {
                "+\(index - current)"
            }
            return Step(id: index, label: label, distance: distance)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(steps) { step in
                        Button {
                            controller.jumpToHistoryStep(step.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                thumbnail
                                Text(step.label)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Text(step.distance)
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(
                                        step.distance == "now"
                                            ? EditorTheme.accent
                                            : EditorTheme.secondaryText
                                    )
                            }
                        }
                    }
                } footer: {
                    Text("History covers this editing session. Recall last ShotDex edit restores the recipe stored in Photos instead.")
                }

                if controller.recalledRecipe != nil {
                    Section {
                        Button("Recall last ShotDex edit") {
                            controller.recallLastEdit()
                            dismiss()
                        }
                        .disabled(!controller.canRecall)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The step thumbnails are the current preview: rendering one image per step
    /// would mean a full Core Image pass per row, which is not worth it in a list
    /// the user scrolls quickly.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 30, height: 30)
            .overlay {
                if let image = controller.editedPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .opacity(0.9)
                }
            }
            .accessibilityHidden(true)
    }
}
