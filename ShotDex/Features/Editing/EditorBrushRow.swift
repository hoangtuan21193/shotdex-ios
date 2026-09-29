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

/// One setting in a pinned pill row: what it reads, how it writes, and what
/// its slider does at the ends.
struct EditorPill: Identifiable {
    let id: String
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let text: (Double) -> String
    let set: (Double) -> Void
    var begin: () -> Void = {}
    var end: () -> Void = {}
}

/// A pinned row of equal pills after optional leading chips (FS-03.13c §3,
/// §4 — the Mask brush and Heal). A tap on a pill turns the row into that
/// setting's slider with ✓ to come back; holding a pill and sliding sideways
/// changes it in place, as fast as the slider would.
struct EditorPillRow<Leading: View, Trailing: View>: View {
    let pills: [EditorPill]
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var editing: String?
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        Group {
            if let editing, let pill = pills.first(where: { $0.id == editing }) {
                sliderRow(pill)
            } else {
                row
            }
        }
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { rowWidth = $0 }
    }

    private var row: some View {
        HStack(spacing: EditorStripLayout.chipSpacing) {
            leading()
            ForEach(pills) { pill in
                let span = pill.range.upperBound - pill.range.lowerBound
                EditorBrushPillButton(
                    title: pill.title,
                    valueText: pill.text(pill.value),
                    sensitivity: span / Double(max(1, rowWidth)),
                    onTap: { withAnimation(EditorTheme.animation) { editing = pill.id } },
                    onHoldBegan: pill.begin,
                    onHoldChanged: { delta in set(pill, pill.value + delta) },
                    onHoldEnded: pill.end,
                    onStep: { up in set(pill, pill.value + (up ? 1 : -1) * span / 20) }
                )
            }
            trailing()
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
    }

    private func set(_ pill: EditorPill, _ new: Double) {
        pill.set(min(pill.range.upperBound, max(pill.range.lowerBound, new)))
    }

    private func sliderRow(_ pill: EditorPill) -> some View {
        HStack(spacing: 0) {
            EditorPlainSliderRow(
                title: pill.title,
                value: pill.value,
                range: pill.range,
                isBipolar: false,
                valueText: pill.text(pill.value),
                isActive: false,
                onBeginDrag: pill.begin,
                onDrag: { set(pill, $0) },
                onEndDrag: pill.end,
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
}

extension EditorPillRow where Trailing == EmptyView {
    init(pills: [EditorPill], @ViewBuilder leading: @escaping () -> Leading) {
        self.init(pills: pills, leading: leading, trailing: { EmptyView() })
    }
}

/// The Mask brush's one pinned row (FS-03.13c §3): Draw and Erase, a hairline,
/// then Size · Feather · Flow. While Size changes, the stage shows the brush
/// ring in the middle of the photo.
struct EditorBrushPinnedRow: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        EditorPillRow(pills: EditorBrushPill.allCases.map(pill)) {
            modeChip(isEraser: false)
            modeChip(isEraser: true)
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 20)
        }
        .onDisappear { chrome.showsBrushSizePreview = false }
    }

    private func pill(_ kind: EditorBrushPill) -> EditorPill {
        EditorPill(
            id: kind.rawValue,
            title: kind.title,
            value: value(kind),
            range: kind.range,
            defaultValue: kind.defaultValue,
            text: { EditorLayoutMetrics.brushAmountText($0, in: kind.range) },
            // Brush settings live on the controller, not the recipe: no history.
            set: { new in
                switch kind {
                case .size: controller.brushSize = new
                case .feather: controller.brushFeather = new
                case .flow: controller.brushFlow = new
                }
            },
            begin: { if kind == .size { chrome.showsBrushSizePreview = true } },
            end: { chrome.showsBrushSizePreview = false }
        )
    }

    private func value(_ kind: EditorBrushPill) -> Double {
        switch kind {
        case .size: controller.brushSize
        case .feather: controller.brushFeather
        case .flow: controller.brushFlow
        }
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
}

/// One pill: its name and a mono number. A tap opens its slider; hold for a
/// quarter second and slide sideways to change it where it is.
struct EditorBrushPillButton: View {
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
        // A 60pt pill on the Duo cover's 326pt list: "Feather 45" needs 0.75.
        .minimumScaleFactor(0.75)
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
