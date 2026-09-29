import SwiftUI
import ShotDexKit

/// One section of the phone's Transform list (FS-03.13b §3). Geometry's
/// sliders come from the adjustment catalog and are drawn by the screen.
struct EditorTransformSectionView: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let section: EditorTransformSection

    /// Auto found nothing: said in the row for 3s, as Upright does — the
    /// editor's toast carries an Undo there would be nothing to undo for.
    @State private var autoNote: String?
    @State private var autoNoteTask: Task<Void, Never>?

    var body: some View {
        switch section {
        case .crop: cropRows
        case .straighten: straightenRows
        case .upright: EditorUprightRow(controller: controller, showsLabel: false)
        case .geometry: EmptyView()
        }
    }

    // MARK: Crop

    private var aspect: CropAspect { controller.recipe.crop.aspect }

    /// Original · Free · 1:1 · 4:5 · More…, equal widths; then Rotate · Flip ·
    /// Reset.
    private var cropRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: EditorStripLayout.chipSpacing) {
                ForEach(EditorCropRatioRow.chips) { option in
                    Button {
                        controller.chooseCropAspect(option, imageAspect: nil)
                    } label: {
                        Text(option.displayName).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorChipButtonStyle(
                        isSelected: aspect == option,
                        horizontalPadding: EditorStripLayout.equalChipHorizontalPadding
                    ))
                    .accessibilityAddTraits(aspect == option ? .isSelected : [])
                }
                moreRatios
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(height: EditorLayoutMetrics.editorPanelRowHeight)

            HStack(spacing: EditorStripLayout.chipSpacing) {
                action("Rotate", icon: "rotate.right", isEnabled: true) { controller.rotate() }
                action(
                    "Flip",
                    icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isEnabled: true
                ) { controller.flip() }
                action("Reset", icon: "arrow.counterclockwise", isEnabled: controller.recipe.crop != .identity) {
                    controller.resetCrop()
                }
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        }
    }

    /// The ratios the row has no chip for. Lit while one of them is the
    /// crop's, which the menu ticks.
    private var moreRatios: some View {
        let isMore = EditorCropRatioRow.more.contains(aspect)
        return Menu {
            ForEach(EditorCropRatioRow.more) { option in
                Button {
                    controller.chooseCropAspect(option, imageAspect: nil)
                } label: {
                    if aspect == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Text("More…").frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(EditorChipButtonStyle(
            isSelected: isMore,
            horizontalPadding: EditorStripLayout.equalChipHorizontalPadding
        ))
        .accessibilityLabel(isMore ? "More ratios, \(aspect.displayName)" : "More ratios")
    }

    private func action(
        _ title: String,
        icon: String,
        isEnabled: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            EditorPanelChipLabel(title: title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: false))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : EditorTheme.rowDisabled)
        .accessibilityLabel(title)
    }

    // MARK: Straighten

    /// Angle, then Straighten Tool; the tool's how-to while it is on.
    private var straightenRows: some View {
        VStack(spacing: 0) {
            angleRow
            HStack(spacing: EditorStripLayout.chipSpacing) {
                Button {
                    chrome.isStraightenToolOn.toggle()
                } label: {
                    EditorPanelChipLabel(title: "Straighten Tool", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: chrome.isStraightenToolOn))
                .accessibilityAddTraits(chrome.isStraightenToolOn ? .isSelected : [])
                Button {
                    showAutoNote(controller.autoStraighten() ? nil : "No straight lines to work from")
                } label: {
                    EditorPanelChipLabel(title: "Auto", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
                .accessibilityLabel("Auto Straighten")
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            if let autoNote {
                Text(autoNote)
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelHint)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            }
            if chrome.isStraightenToolOn {
                Text("Drag a line along something that should be level, like the horizon or a table edge.")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelHint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(EditorTheme.animation, value: chrome.isStraightenToolOn)
        .animation(EditorTheme.animation, value: autoNote)
        .onDisappear { autoNoteTask?.cancel() }
    }

    private func showAutoNote(_ message: String?) {
        autoNoteTask?.cancel()
        autoNote = message
        guard message != nil else { return }
        autoNoteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            autoNote = nil
        }
    }

    private var angleRow: some View {
        EditorPlainSliderRow(
            title: "Angle",
            value: controller.recipe.crop.straightenDegrees,
            range: -45...45,
            isBipolar: true,
            valueText: String(format: "%.1f°", controller.recipe.crop.straightenDegrees),
            isActive: false,
            detent: 0,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setStraighten($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setStraighten(0) }
        )
    }
}
