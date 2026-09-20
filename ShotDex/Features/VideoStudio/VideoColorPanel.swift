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
                Divider().overlay(EditorTheme.panelDivider)
                windowsSection
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

    // MARK: Windows and qualifiers

    /// Resolve calls these power windows and the HSL qualifier; the model
    /// behind them is the photo editor's own `PhotoMask`, so a window means
    /// the same thing in both editors.
    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Windows & Qualifiers", comment: "Video Studio colour: masked, local grades")
                .font(EditorTheme.groupLabel)
                .foregroundStyle(EditorTheme.secondaryText)

            HStack(spacing: 6) {
                ForEach(VideoMaskRenderer.supportedKinds) { kind in
                    Button { model.addMask(kind) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: kind.videoSystemImage)
                                .font(.system(size: 14, weight: .medium))
                            Text(kind.displayName)
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                                .fill(EditorTheme.trackChip)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Add \(kind.displayName) window", comment: "Video Studio colour: adds one local grade"))
                }
            }

            if model.recipe.masks.isEmpty {
                Text(
                    "A window grades part of the frame. Brush, subject and sky are photo-only — they need a pass per frame.",
                    comment: "Video Studio colour: empty state for windows, and which kinds are absent"
                )
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
            }

            ForEach(model.recipe.masks) { mask in
                maskRow(mask)
            }

            if let mask = model.selectedMask {
                maskControls(mask)
            }
        }
    }

    private func maskRow(_ mask: PhotoMask) -> some View {
        let isOn = mask.id == model.selectedMaskID
        return HStack(spacing: 8) {
            Button { model.selectedMaskID = isOn ? nil : mask.id } label: {
                Text(mask.name)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? EditorTheme.accent : .white)
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)

            Button { model.toggleMaskInverted(mask.id) } label: {
                Image(systemName: mask.isInverted ? "circle.righthalf.filled" : "circle.lefthalf.filled")
                    .foregroundStyle(mask.isInverted ? EditorTheme.accent : EditorTheme.dimText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Invert window", comment: "Video Studio colour: grades outside the window instead of inside"))

            Button { model.toggleMaskVisible(mask.id) } label: {
                Image(systemName: mask.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(mask.isVisible ? EditorTheme.dimText : EditorTheme.timelineDestructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show window", comment: "Video Studio colour: turns one window off without deleting it"))

            Button { model.removeMask(mask.id) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(EditorTheme.timelineDestructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete window", comment: "Video Studio colour"))
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func maskControls(_ mask: PhotoMask) -> some View {
        if let component = mask.components.first {
            VStack(spacing: 0) {
                switch component.kind {
                case .radialGradient:
                    slider("Size", component.radiusX, 0.05...1) { value in
                        model.updateSelectedMaskComponent { $0.radiusX = value; $0.radiusY = value }
                    }
                    slider("Feather", component.feather, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.feather = value }
                    }
                case .luminanceRange:
                    slider("From", component.luminanceMinimum, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.luminanceMinimum = value }
                    }
                    slider("To", component.luminanceMaximum, 0...1) { value in
                        model.updateSelectedMaskComponent { $0.luminanceMaximum = value }
                    }
                case .colorRange:
                    slider("Tolerance", component.colorTolerance, 0.02...1) { value in
                        model.updateSelectedMaskComponent { $0.colorTolerance = value }
                    }
                default:
                    EmptyView()
                }
                // What the window actually does to the picture it covers.
                slider("Exposure", mask.adjustments[.exposure], -1...1) { value in
                    model.updateSelectedMaskAdjustment(.exposure, value: value)
                }
                slider("Saturation", mask.adjustments[.saturation], -1...1) { value in
                    model.updateSelectedMaskAdjustment(.saturation, value: value)
                }
            }
        }
    }

    private func slider(
        _ label: String,
        _ value: Double,
        _ range: ClosedRange<Double>,
        set: @escaping (Double) -> Void
    ) -> some View {
        InspectorSlider(
            label: label,
            value: value,
            range: range,
            valueText: String(format: "%.2f", value),
            model: model,
            set: set,
            reset: { model.pushUndo(); set(range.lowerBound <= 0 ? 0 : range.lowerBound) }
        )
    }
}

extension PhotoMaskComponentKind {
    /// The glyph the Video Studio uses for each window it supports.
    var videoSystemImage: String {
        switch self {
        case .radialGradient: "circle.dashed"
        case .linearGradient: "line.diagonal"
        case .luminanceRange: "circle.lefthalf.filled"
        case .colorRange: "eyedropper"
        default: "square.dashed"
        }
    }
}
