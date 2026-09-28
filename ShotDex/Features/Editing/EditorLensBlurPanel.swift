import SwiftUI
import ShotDexKit

/// The Lens Blur group (FS-03.15e §1): Amount, the bokeh's shape, the depth
/// band kept sharp, and Visualize Depth. A tap on the photo while the group
/// is open re-focuses the band on the depth under the finger.
struct EditorLensBlurSection: View {
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = controller.lensBlurStatusText {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if controller.isEstimatingDepth {
                        ProgressView().controlSize(.mini)
                    }
                    Text(status)
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
            Group {
                slider("Amount", value: controller.recipe.lensBlur.amount) { blur, value in
                    blur.amount = value
                }
                bokehRow
                slider("Near", value: controller.recipe.lensBlur.focusNear) { blur, value in
                    blur.focusNear = max(value, blur.focusFar)
                }
                slider("Far", value: controller.recipe.lensBlur.focusFar) { blur, value in
                    blur.focusFar = min(value, blur.focusNear)
                }
                EditorToggleRow(
                    title: "Visualize Depth",
                    isOn: controller.isVisualizingDepth
                ) { controller.isVisualizingDepth = $0 }
            }
            .disabled(!controller.isLensBlurAvailable)
            .opacity(controller.isLensBlurAvailable ? 1 : EditorTheme.rowDisabled)
            Color.clear.frame(height: 16)
        }
        .editorPanelScroll(panelScrolls)
        .scrollDisabled(chrome.activePlainSliderID != nil)
        .onAppear { controller.prepareLensBlurDepth() }
        .onDisappear { controller.isVisualizingDepth = false }
    }

    private var bokehRow: some View {
        HStack(spacing: 6) {
            ForEach(PhotoBokehShape.allCases) { shape in
                let isSelected = controller.recipe.lensBlur.bokeh == shape
                Button {
                    controller.updateLensBlur { $0.bokeh = shape }
                } label: {
                    Text(shape.displayName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: isSelected, horizontalPadding: 4))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }

    private func slider(
        _ title: String,
        value: Double,
        set: @escaping (inout PhotoLensBlurRecipe, Double) -> Void
    ) -> some View {
        let sliderID = "lensBlur.\(title)"
        return EditorPlainSliderRow(
            title: title,
            value: value * 100,
            range: 0...100,
            isBipolar: false,
            valueText: "\(Int((value * 100).rounded()))",
            isActive: chrome.activePlainSliderID == sliderID,
            onBeginDrag: {
                controller.beginContinuousChange()
                chrome.activePlainSliderID = sliderID
            },
            onDrag: { newValue in
                controller.updateLensBlur { set(&$0, newValue / 100) }
            },
            onEndDrag: {
                controller.endContinuousChange()
                chrome.activePlainSliderID = nil
            },
            onReset: {
                let identity = PhotoLensBlurRecipe.identity
                controller.updateLensBlur {
                    switch title {
                    case "Amount": $0.amount = identity.amount
                    case "Near": $0.focusNear = identity.focusNear
                    default: $0.focusFar = identity.focusFar
                    }
                }
            }
        )
    }
}
