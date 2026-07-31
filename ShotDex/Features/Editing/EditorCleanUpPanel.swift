import SwiftUI
import UIKit

/// The Clean Up tool: pick a mode, set the brush, then manage what you removed.
///
/// The stroke list is the reason this panel exists rather than leaving Clean Up
/// to undo alone — after taking out ten spots, fixing the second one should not
/// cost nine undos.
struct EditorCleanUpPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        brushRows
                    } header: {
                        EditorGroupHeader(title: "Brush", isFirst: true)
                    }
                    if let stroke = controller.selectedCleanUpStroke {
                        Section {
                            selectedRows(stroke)
                        } header: {
                            EditorGroupHeader(title: "Selected \u{00B7} \(stroke.mode.displayName)")
                        }
                    }
                    Section {
                        strokeRows
                    } header: {
                        EditorGroupHeader(
                            title: strokeSectionTitle,
                            onReset: controller.cleanUpStrokes.isEmpty
                                ? nil
                                : { controller.resetCleanUp() }
                        )
                    }
                    Color.clear.frame(height: 16)
                }
            }
            .scrollDisabled(chrome.activePlainSliderID != nil)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CleanUpMode.allCases) { mode in
                let isSelected = controller.cleanUpMode == mode
                Button {
                    withAnimation(EditorTheme.animation) { controller.cleanUpMode = mode }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Color.white : EditorTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(isSelected ? EditorTheme.accent : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(EditorTheme.control, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var brushRows: some View {
        // Size and Feather belong to the tool, not to the recipe, so they are
        // deliberately outside undo — the same call the mask brush makes.
        EditorPlainSliderRow(
            title: "Size",
            value: controller.cleanUpSize * 100,
            range: EditorLayoutMetrics.cleanUpSizeRange.lowerBound * 100
                ... EditorLayoutMetrics.cleanUpSizeRange.upperBound * 100,
            isBipolar: false,
            valueText: percent(controller.cleanUpSize),
            isActive: chrome.activePlainSliderID == "cleanup.size",
            onBeginDrag: { beginPlainDrag("cleanup.size") },
            onDrag: { controller.cleanUpSize = $0 / 100 },
            onEndDrag: { chrome.activePlainSliderID = nil },
            onReset: { controller.cleanUpSize = EditorLayoutMetrics.cleanUpDefaultSize }
        )
        EditorPlainSliderRow(
            title: "Feather",
            value: controller.cleanUpFeather * 100,
            range: 0...100,
            isBipolar: false,
            valueText: percent(controller.cleanUpFeather),
            isActive: chrome.activePlainSliderID == "cleanup.feather",
            onBeginDrag: { beginPlainDrag("cleanup.feather") },
            onDrag: { controller.cleanUpFeather = $0 / 100 },
            onEndDrag: { chrome.activePlainSliderID = nil },
            onReset: { controller.cleanUpFeather = EditorLayoutMetrics.cleanUpDefaultFeather }
        )
        if controller.cleanUpMode == .remove {
            if controller.hasCleanUpModel {
                EditorToggleRow(
                    title: "AI Fill",
                    isOn: controller.usesAICleanUp,
                    onChange: { controller.usesAICleanUp = $0 }
                )
                caption("Applies to new Remove strokes. Long-press a stroke below to switch it.")
            } else {
                caption("Remove fills from the surrounding pixels. AI Fill needs the "
                    + "inpainting model, which this build does not include.")
            }
        } else {
            caption("Paint the flaw, then drag the source circle on the photo to choose "
                + "where the pixels come from.")
        }
    }

    @ViewBuilder
    private func selectedRows(_ stroke: CleanUpStroke) -> some View {
        EditorPlainSliderRow(
            title: "Opacity",
            value: stroke.opacity * 100,
            range: 0...100,
            isBipolar: false,
            valueText: percent(stroke.opacity),
            isActive: chrome.activePlainSliderID == "cleanup.opacity",
            detent: 100,
            onBeginDrag: {
                controller.beginContinuousChange()
                beginPlainDrag("cleanup.opacity")
            },
            onDrag: { controller.setSelectedCleanUpOpacity($0 / 100) },
            onEndDrag: {
                chrome.activePlainSliderID = nil
                controller.endContinuousChange()
            },
            onReset: { controller.setSelectedCleanUpOpacity(1) }
        )
        HStack {
            Spacer(minLength: 0)
            Button("Delete Stroke") { controller.removeCleanUpStroke(id: stroke.id) }
                .buttonStyle(EditorTextButtonStyle())
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var strokeRows: some View {
        if controller.cleanUpStrokes.isEmpty {
            caption(controller.cleanUpMode == .remove
                ? "Brush over whatever you want gone."
                : "Brush over the flaw to start.")
        } else {
            ForEach(Array(controller.cleanUpStrokes.enumerated()), id: \.element.id) { pair in
                strokeRow(pair.element, number: pair.offset + 1)
            }
        }
    }

    private func strokeRow(_ stroke: CleanUpStroke, number: Int) -> some View {
        let isSelected = controller.selectedCleanUpStrokeID == stroke.id
        return Button {
            controller.selectCleanUpStroke(id: stroke.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: stroke.mode.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.secondaryText)
                    .frame(width: 22)
                Text("\(stroke.mode.displayName) \(number)")
                    .font(EditorTheme.maskTitle)
                    .foregroundStyle(.white)
                if stroke.usesModel {
                    Text("AI")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(EditorTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(EditorTheme.accent.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 0)
                if stroke.opacity < 0.999 {
                    Text(percent(stroke.opacity))
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.dimText)
                }
                Button {
                    controller.removeCleanUpStroke(id: stroke.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(stroke.mode.displayName) \(number)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(height: 40)
            .background(isSelected ? EditorTheme.control : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            // Switching an existing stroke between fills lives here rather than as
            // a second toggle in the panel: two "AI Fill" switches one above the
            // other, one for new strokes and one for this one, reads as a bug.
            if stroke.mode == .remove, controller.hasCleanUpModel {
                Button(stroke.usesModel ? "Fill Without AI" : "Fill With AI") {
                    controller.selectCleanUpStroke(id: stroke.id)
                    controller.setSelectedCleanUpUsesModel(!stroke.usesModel)
                }
            }
            Button("Delete", role: .destructive) {
                controller.removeCleanUpStroke(id: stroke.id)
            }
        }
    }

    private var strokeSectionTitle: String {
        controller.cleanUpStrokes.isEmpty
            ? "Strokes"
            : "Strokes \u{00B7} \(controller.cleanUpStrokes.count)"
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginPlainDrag(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chrome.activePlainSliderID = id
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
