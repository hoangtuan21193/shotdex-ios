import SwiftUI
import ShotDexKit

/// The grading stage, as one scrolling panel rather than a second page.
///
/// Resolve puts this behind a whole Color page with a node graph, scopes,
/// qualifier, power windows and a tracker. That is a colourist's workspace,
/// and the node graph in particular only earns its screen once a grade has
/// branches. What a photographer cutting a short film actually reaches for is
/// the front of that page: undo the log, set the three primaries, bend the
/// curve. Those are here, and the render maths behind them is the photo
/// editor's — `PhotoRenderService.applyColor` and `.applyCurve`, already
/// shipping, already unit-tested.
///
/// What is deliberately absent: nodes, windows, tracking, qualifier. Not
/// because the hardware could not run them, but because each one is a tool
/// for a job — isolating a face, following it across a shot — that this
/// screen is not for.
struct VideoColorPanel: View {
    @Bindable var model: VideoStudioModel

    @State private var region: ColorGradingRegion = .midtones

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                inputTransformSection
                Divider().overlay(EditorTheme.panelDivider)
                primariesSection
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }

    // MARK: Input transform

    private var inputTransformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input Transform", comment: "Video Studio colour: undoing the camera's encoding")
                .font(EditorTheme.groupLabel)
                .foregroundStyle(EditorTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VideoInputTransform.allCases) { transform in
                        transformChip(transform)
                    }
                }
            }

            Text(model.recipe.inputTransform.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)

            if !model.recipe.inputTransform.isIdentity {
                Text(
                    "Transfer function only — a wide-gamut capture keeps its primaries.",
                    comment: "Video Studio colour: what the input transform does not do"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(EditorTheme.dimText)
            }
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private func transformChip(_ transform: VideoInputTransform) -> some View {
        let isOn = model.recipe.inputTransform == transform
        return Button { model.setInputTransform(transform) } label: {
            Text(transform.title)
                .font(EditorTheme.pillLabel)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(isOn ? EditorTheme.accent : EditorTheme.trackChip)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Primaries

    private var primariesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Primaries", comment: "Video Studio colour: the three grading wheels")
                    .font(EditorTheme.groupLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
                Button {
                    model.resetColor()
                } label: {
                    Text("Reset", comment: "Video Studio colour: puts the whole grade back to neutral")
                        .font(EditorTheme.pillLabel)
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.recipe.color.isIdentity)
            }

            Picker("Region", selection: $region) {
                ForEach(ColorGradingRegion.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.segmented)

            EditorColorWheel(
                hue: wheel.hue,
                saturation: wheel.saturation,
                diameter: 150,
                onBegin: { model.pushUndo() },
                onChange: { hue, saturation in
                    model.setGradingWheel(region, hue: hue, saturation: saturation)
                },
                onEnd: {},
                onReset: { model.resetGrading(region) }
            )
            .frame(maxWidth: .infinity)

            InspectorSlider(
                label: "Luminance",
                value: wheel.luminance,
                range: -1...1,
                valueText: String(format: "%+.2f", wheel.luminance),
                model: model,
                set: { model.setGradingLuminance(region, $0) },
                reset: { model.pushUndo(); model.setGradingLuminance(region, 0) }
            )
        }
    }

    private var wheel: ColorGradingAdjustments.Wheel {
        model.recipe.color.grading[region]
    }
}
