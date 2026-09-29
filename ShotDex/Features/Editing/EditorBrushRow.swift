import SwiftUI

/// A brush setting shown as a pill in the pinned brush row (FS-03.13c §3).
enum EditorBrushPill: String, CaseIterable, Identifiable {
    case size, feather, flow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: "Size"
        case .feather: "Feather"
        case .flow: "Flow"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .size: EditorLayoutMetrics.brushSizeRange
        case .feather: 0...1
        case .flow: 0.05...1
        }
    }

    var defaultValue: Double {
        switch self {
        case .size: 0.25
        case .feather: 0.45
        case .flow: 0.8
        }
    }
}

/// The Mask brush's one pinned row (FS-03.13c §3): Draw and Erase, a hairline,
/// then Size · Feather · Flow as equal pills. A tap on a pill turns the row
/// into that setting's slider with ✓ to come back; holding a pill and sliding
/// sideways changes it in place, as fast as the slider would. While Size
/// changes, the stage shows the brush ring in the middle of the photo.
struct EditorBrushPinnedRow: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    @State private var editing: EditorBrushPill?
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        Group {
            if let editing {
                sliderRow(editing)
            } else {
                pills
            }
        }
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { rowWidth = $0 }
        .onDisappear { chrome.showsBrushSizePreview = false }
    }

    private var pills: some View {
        HStack(spacing: EditorStripLayout.chipSpacing) {
            modeChip(isEraser: false)
            modeChip(isEraser: true)
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 20)
            ForEach(EditorBrushPill.allCases) { pill in
                EditorBrushPillButton(
                    title: pill.title,
                    valueText: EditorLayoutMetrics.brushAmountText(value(pill), in: pill.range),
                    sensitivity: (pill.range.upperBound - pill.range.lowerBound) / Double(max(1, rowWidth)),
                    onTap: { withAnimation(EditorTheme.animation) { editing = pill } },
                    onHoldBegan: { begin(pill) },
                    onHoldChanged: { delta in set(pill, value(pill) + delta) },
                    onHoldEnded: { end(pill) },
                    onStep: { up in
                        set(pill, value(pill) + (up ? 1 : -1) * (pill.range.upperBound - pill.range.lowerBound) / 20)
                    }
                )
            }
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
    }

    private func modeChip(isEraser: Bool) -> some View {
        let isOn = controller.brushIsEraser == isEraser
        return Button {
            controller.maskOperation = isEraser ? .subtract : .add
        } label: {
            Image(systemName: isEraser ? "eraser" : "paintbrush.pointed")
                .font(.system(size: 15))
                .frame(width: 40 - 2 * EditorStripLayout.chipHorizontalPadding)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: isOn))
        .accessibilityLabel(isEraser ? "Erase" : "Draw")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sliderRow(_ pill: EditorBrushPill) -> some View {
        HStack(spacing: 0) {
            EditorPlainSliderRow(
                title: pill.title,
                value: value(pill),
                range: pill.range,
                isBipolar: false,
                valueText: EditorLayoutMetrics.brushAmountText(value(pill), in: pill.range),
                isActive: false,
                onBeginDrag: { begin(pill) },
                onDrag: { set(pill, $0) },
                onEndDrag: { end(pill) },
                onReset: { set(pill, pill.defaultValue) }
            )
            Button {
                withAnimation(EditorTheme.animation) { editing = nil }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .padding(.trailing, AppTheme.Spacing.sm)
        }
    }

    // MARK: Values

    private func value(_ pill: EditorBrushPill) -> Double {
        switch pill {
        case .size: controller.brushSize
        case .feather: controller.brushFeather
        case .flow: controller.brushFlow
        }
    }

    /// Brush settings live on the controller, not the recipe: no history.
    private func set(_ pill: EditorBrushPill, _ new: Double) {
        let clamped = min(pill.range.upperBound, max(pill.range.lowerBound, new))
        switch pill {
        case .size: controller.brushSize = clamped
        case .feather: controller.brushFeather = clamped
        case .flow: controller.brushFlow = clamped
        }
    }

    private func begin(_ pill: EditorBrushPill) {
        if pill == .size { chrome.showsBrushSizePreview = true }
    }

    private func end(_ pill: EditorBrushPill) {
        chrome.showsBrushSizePreview = false
    }
}

/// One pill: its name and a mono number. A tap opens its slider; hold for a
/// quarter second and slide sideways to change it where it is.
private struct EditorBrushPillButton: View {
    let title: String
    let valueText: String
    /// Value per point of horizontal travel — the slider's own rate.
    let sensitivity: Double
    let onTap: () -> Void
    let onHoldBegan: () -> Void
    let onHoldChanged: (Double) -> Void
    let onHoldEnded: () -> Void
    /// VoiceOver's swipe up / down: a twentieth of the range.
    let onStep: (Bool) -> Void

    @State private var pressedAt: Date?
    @State private var isHolding = false
    @State private var lastX: CGFloat = 0

    private static let holdDelay: TimeInterval = 0.25
    private static let tapSlop: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .font(EditorTheme.chipLabel)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
        .frame(maxWidth: .infinity)
        .frame(height: EditorStripLayout.chipHeight)
        .background(
            isHolding ? EditorTheme.chipSelected : EditorTheme.chipIdle,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let now = Date()
                    if pressedAt == nil {
                        pressedAt = now
                        lastX = value.location.x
                    }
                    if !isHolding, let pressedAt, now.timeIntervalSince(pressedAt) >= Self.holdDelay,
                       abs(value.translation.width) < Self.tapSlop {
                        isHolding = true
                        lastX = value.location.x
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onHoldBegan()
                    }
                    guard isHolding else { return }
                    onHoldChanged(Double(value.location.x - lastX) * sensitivity)
                    lastX = value.location.x
                }
                .onEnded { value in
                    if isHolding {
                        onHoldEnded()
                    } else if hypot(value.translation.width, value.translation.height) < Self.tapSlop {
                        onTap()
                    }
                    pressedAt = nil
                    isHolding = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityAction { onTap() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(true)
            case .decrement: onStep(false)
            @unknown default: break
            }
        }
    }
}
