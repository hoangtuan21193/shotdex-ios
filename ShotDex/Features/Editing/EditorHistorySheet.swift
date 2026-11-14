import SwiftUI

/// One recorded step: what it changed, and how far back it is from where the
/// session currently stands. Shared by the phone's sheet and the wide layout's
/// in-panel list so the two cannot drift.
struct EditorHistoryStep: Identifiable {
    let id: Int
    let label: String
    let distance: String

    /// Newest first. The labels are derived by diffing neighbouring recipes
    /// rather than being recorded up front.
    @MainActor
    static func steps(of controller: PhotoEditorController) -> [EditorHistoryStep] {
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
            return EditorHistoryStep(id: index, label: label, distance: distance)
        }
    }
}

/// Every recorded step of the session, as a sheet. The phone's route: there is
/// no panel to put a list in, so it takes the screen.
struct EditorHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: PhotoEditorController

    private var steps: [EditorHistoryStep] { EditorHistoryStep.steps(of: controller) }

    var body: some View {
        NavigationStack {
            List {
                snapshotSection
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

    @State private var isNamingSnapshot = false
    @State private var snapshotName = ""

    /// Named states kept with the photo (FS-03.18 §5), above this session's
    /// steps: tap to go back, swipe to delete.
    private var snapshotSection: some View {
        Section {
            ForEach(controller.snapshots) { snapshot in
                Button {
                    controller.applySnapshot(snapshot)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.name)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { controller.deleteSnapshot(snapshot) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Text("Snapshots")
                Spacer()
                Button {
                    snapshotName = ""
                    isNamingSnapshot = true
                } label: {
                    Label("Snapshot", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(EditorTheme.accent)
                .accessibilityLabel("Add Snapshot")
            }
        } footer: {
            if controller.snapshots.isEmpty {
                Text("Keep the photo as it looks now under a name, and come back to it later — even after closing the editor.")
            }
        }
        .alert("New Snapshot", isPresented: $isNamingSnapshot) {
            TextField("Name", text: $snapshotName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { controller.addSnapshot(named: snapshotName) }
        }
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

/// The same history, as a column inside the wide layout's tools panel.
///
/// Not a sheet, because a sheet is the wrong shape for this on two counts. You
/// pick a history step by *looking at the photo it produces*, and a sheet covers
/// the photo — and on a window that is regular-width but compact-height (the
/// iPhone Duo's inner display, 951×669) UIKit ignores `presentationDetents`
/// entirely, so `.medium` and `.large` both resolve to full screen and the photo
/// goes away completely. The rail already has a History stop; this is what it
/// opens.
///
/// Tier D throughout: plain rows on `panelSolid`, no `List` and no
/// `NavigationStack` — DESIGN.md §2 does not allow a tier-A container inside a
/// tier-D surface, which the sheet version gets away with only by being a sheet.
struct EditorHistoryPanel: View {
    @Bindable var controller: PhotoEditorController

    private var steps: [EditorHistoryStep] { EditorHistoryStep.steps(of: controller) }

    @State private var isNamingSnapshot = false
    @State private var snapshotName = ""

    var body: some View {
        VStack(spacing: 0) {
            snapshotRows
            ForEach(steps) { step in
                Button {
                    controller.jumpToHistoryStep(step.id)
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        thumbnail
                        Text(step.label)
                            .font(.system(size: 13))
                            .foregroundStyle(
                                step.distance == "now" ? .white : Color.white.opacity(0.75)
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: AppTheme.Spacing.sm)
                        Text(step.distance)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(
                                step.distance == "now"
                                    ? EditorTheme.accent
                                    : EditorTheme.secondaryText
                            )
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .frame(minHeight: AppTheme.Size.minTouch)
                    .background(step.distance == "now" ? EditorTheme.activeRow : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(step.label)
                .accessibilityValue(step.distance == "now" ? "Current step" : step.distance)

                Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
            }

            if controller.recalledRecipe != nil {
                Button {
                    controller.recallLastEdit()
                } label: {
                    Text("Recall last ShotDex edit")
                        .font(EditorTheme.rowLabel)
                        .foregroundStyle(
                            controller.canRecall ? EditorTheme.accent : EditorTheme.dimText
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(height: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controller.canRecall)
                .hoverEffect(.highlight)
            }

            Text("History covers this editing session. Recall last ShotDex edit restores the recipe stored in Photos instead.")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.md)
        }
    }

    /// Snapshots (FS-03.18 §5) above the steps: a header with + Snapshot, one
    /// row each — tap to go back, long-press to delete.
    private var snapshotRows: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SNAPSHOTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer()
                Button {
                    snapshotName = ""
                    isNamingSnapshot = true
                } label: {
                    Label("Snapshot", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorTheme.accent)
                        .frame(minHeight: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Snapshot")
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            ForEach(controller.snapshots) { snapshot in
                Button {
                    controller.applySnapshot(snapshot)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(minHeight: AppTheme.Size.minTouch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .contextMenu {
                    Button(role: .destructive) { controller.deleteSnapshot(snapshot) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
        }
        .alert("New Snapshot", isPresented: $isNamingSnapshot) {
            TextField("Name", text: $snapshotName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { controller.addSnapshot(named: snapshotName) }
        }
    }

    /// Same reasoning as the sheet's: rendering one image per step would be a
    /// full Core Image pass per row.
    private var thumbnail: some View {
        RoundedRectangle.app(AppTheme.Radius.sm)
            .fill(Color.white.opacity(0.06))
            .frame(width: 28, height: 28)
            .overlay {
                if let image = controller.editedPreviewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
                        .opacity(0.9)
                }
            }
            .accessibilityHidden(true)
    }
}
