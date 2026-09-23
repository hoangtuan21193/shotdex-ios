import ShotDexKit
import SwiftUI

/// The panorama screen's controls, in the order the picture is built:
/// projection first, then what is cropped away, then how big it is saved
/// (FS-14.01 §3).
struct PanoramaMergePanel: View {
    @Bindable var model: PanoramaMergeModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            projection
            Divider().overlay(EditorTheme.panelDivider)
            EditorToggleRow(title: String(localized: "Auto Crop"), isOn: model.autoCrop) {
                model.autoCrop = $0
            }
            Divider().overlay(EditorTheme.panelDivider)
            size
            Divider().overlay(EditorTheme.panelDivider)
            arrange
        }
        .disabled(model.isSaving)
    }

    // MARK: Arrange

    /// The way out when the automatic placement got a frame wrong. Last in the
    /// panel because it is the exception, not the setting (FS-14.01 §3).
    private var arrange: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                model.toggleArrange()
            } label: {
                HStack {
                    Label(
                        model.isArranging ? "Done Arranging" : "Arrange",
                        systemImage: "square.on.square.dashed"
                    )
                    .font(EditorTheme.rowLabel)
                    Spacer()
                    if model.isArrangingFrame {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppTheme.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isArranging ? EditorTheme.accent : .white)
            .disabled(!model.canArrange)
            Text(
                model.isArranging
                    ? "Drag a photo to where it belongs, or off the panorama to set it aside."
                    : "Move a photo the automatic placement got wrong."
            )
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Projection

    private var projection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("PROJECTION")
                .font(EditorTheme.groupLabel)
                .tracking(0.6)
                .foregroundStyle(EditorTheme.secondaryText)
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(PanoramaProjectionKind.allCases, id: \.self) { kind in
                    let availability = model.availability.first { $0.kind == kind }
                    let enabled = availability?.isAvailable ?? true
                    Button {
                        model.projection = kind
                    } label: {
                        Text(kind.title)
                            .font(EditorTheme.rowLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PanoramaChoiceStyle(isSelected: model.projection == kind))
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                    .accessibilityHint(enabled ? "" : (availability?.reason?.sentence ?? ""))
                }
            }
            // One line saying what this projection is *for*, or why it cannot
            // be built — never what it does arithmetically, which is already
            // visible in the picture (DESIGN.md §10.3b).
            Text(projectionExplanation)
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.dimText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var projectionExplanation: String {
        let availability = model.availability.first { $0.kind == model.projection }
        if let reason = availability?.reason { return reason.sentence }
        return model.projection.explanation
    }

    // MARK: Size

    private var size: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            EditorValueSlider(
                label: String(localized: "Size"),
                value: model.sizeScale * 100,
                range: 25...100,
                valueText: "\(Int((model.sizeScale * 100).rounded()))%",
                // Snaps at full size: anything less is a choice, and it should
                // take a deliberate drag to leave.
                detent: 100,
                accessibilityName: String(localized: "Output size"),
                onBeginDrag: {},
                onDrag: { model.sizeScale = min(1, max(0.25, $0 / 100)) },
                onReset: { model.sizeScale = 1 }
            )
            // One line, the size the photo will be: pixels and megapixels are
            // exact, file and wait are measured off the preview (FS-14.01 §4b).
            Text(model.estimateText ?? String(localized: "Full size keeps every pixel the frames had."))
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(model.spaceShortfall == nil ? AnyShapeStyle(EditorTheme.dimText) : AnyShapeStyle(Color.red))
                .fixedSize(horizontal: false, vertical: true)
                .animation(nil, value: model.sizeScale)
        }
    }
}

/// The chip a projection is chosen with. Drawn rather than a segmented picker
/// because one of them can be unavailable, and a segmented control has no way
/// to say so.
private struct PanoramaChoiceStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black : .white)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                isSelected ? EditorTheme.accent : EditorTheme.control,
                in: RoundedRectangle.app(AppTheme.Radius.md)
            )
            .overlay {
                RoundedRectangle.app(AppTheme.Radius.md)
                    .stroke(isSelected ? EditorTheme.accent : EditorTheme.hairline, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .hoverEffect(.highlight)
    }
}

extension PanoramaProjectionKind {
    var title: String {
        switch self {
        case .spherical: String(localized: "Spherical")
        case .cylindrical: String(localized: "Cylindrical")
        case .perspective: String(localized: "Perspective")
        }
    }

    /// What the projection is *for*, in the voice the combine modes use.
    var explanation: String {
        switch self {
        case .spherical:
            String(localized: "Works for any sweep, including a full circle. Straight lines bend near the edges.")
        case .cylindrical:
            String(localized: "Keeps buildings upright. Best for a single row across a skyline.")
        case .perspective:
            String(localized: "One flat photograph, as if shot on a wider lens. Only for a narrow sweep.")
        }
    }
}

extension PanoramaProjectionUnavailableReason {
    /// Why this projection cannot be built, in plain words.
    var sentence: String {
        switch self {
        case .verticalSweepTooWide:
            String(localized: "These photos cover too much sky and ground for this projection.")
        case .horizontalSweepTooWide:
            String(localized: "These photos cover too wide a sweep for a single flat photograph.")
        }
    }
}
