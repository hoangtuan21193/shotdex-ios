import SwiftUI
import UIKit

/// One adjustment row: label · track · value.
///
/// The three columns are also the gesture rule from the spec. Label and value
/// take taps only, so a pan that starts there always scrolls. The track hands the
/// pan to `SliderPanCatcher`, which decides after 10pt whether the scroll view or
/// the slider owns the gesture — never both — and only writes a value once the
/// finger has moved 6pt.
struct EditorSliderRow: View {
    let kind: PhotoAdjustmentKind
    let value: Double
    let isActive: Bool
    let onBeginDrag: () -> Void
    let onDrag: (Double) -> Void
    let onEndDrag: (Double, Double, Bool) -> Void
    let onReset: () -> Void
    let onEditValue: () -> Void

    @State private var dragStartValue = 0.0
    @State private var dragStartDate = Date()
    @State private var hasActivated = false
    @State private var isHoldingDetent = false

    private var range: ClosedRange<Double> { EditorAdjustmentCatalog.sliderRange(of: kind) }
    private var isBipolar: Bool { EditorAdjustmentCatalog.isBipolar(kind) }
    private var isZero: Bool {
        abs(value - PhotoAdjustments()[kind]) < 0.0001
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(EditorAdjustmentCatalog.shortTitle(of: kind))
                .font(EditorTheme.rowLabel)
                .foregroundStyle(isZero ? EditorTheme.secondaryText : .white)
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.sliderLabelWidth, alignment: .leading)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onReset()
                }
                .accessibilityHint("Double tap to reset")

            track

            Text(EditorAdjustmentCatalog.displayText(value, of: kind))
                .font(EditorTheme.rowValue)
                .foregroundStyle(isZero ? EditorTheme.dimText : EditorTheme.accent)
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.sliderValueWidth, alignment: .trailing)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEditValue)
                .accessibilityHint("Tap to type a value")
        }
        .padding(.horizontal, 14)
        .background(isActive ? EditorTheme.activeRow : .clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(EditorAdjustmentCatalog.displayText(value, of: kind))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 40
            let next = direction == .increment ? value + step : value - step
            let clamped = min(range.upperBound, max(range.lowerBound, next))
            onDrag(clamped)
            onEndDrag(value, clamped, false)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = normalizedFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(EditorTheme.troughGradient(for: kind) ?? troughFill)
                    .frame(height: isActive ? 4 : 3)

                if isBipolar {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 1, height: 8)
                        .offset(x: width / 2 - 0.5)
                }

                fill(width: width, fraction: fraction)

                Circle()
                    .fill(.white)
                    .frame(width: isActive ? 20 : 16, height: isActive ? 20 : 16)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .overlay {
                        if isActive {
                            Circle()
                                .fill(EditorTheme.accent.opacity(0.3))
                                .frame(width: 34, height: 34)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(x: min(width - 16, max(0, fraction * width - 8)))
            }
            .frame(height: EditorLayoutMetrics.sliderRowHeight)
            .frame(maxHeight: .infinity)
            .overlay {
                SliderPanCatcher(
                    onBegan: {
                        dragStartValue = value
                        dragStartDate = Date()
                        hasActivated = false
                        isHoldingDetent = abs(value - PhotoAdjustments()[kind]) < 0.0001
                        onBeginDrag()
                    },
                    onChanged: { translation in
                        guard width > 0 else { return }
                        guard abs(translation) >= EditorLayoutMetrics.sliderActivationDistance
                        else { return }
                        hasActivated = true
                        let span = range.upperBound - range.lowerBound
                        let proposed = dragStartValue + Double(translation / width) * span
                        onDrag(
                            detented(
                                min(range.upperBound, max(range.lowerBound, proposed)),
                                trackWidth: width
                            )
                        )
                    },
                    onEnded: { _ in
                        let wasQuick = Date().timeIntervalSince(dragStartDate) < 0.25
                        onEndDrag(dragStartValue, value, hasActivated && wasQuick)
                        hasActivated = false
                    }
                )
            }
        }
        .frame(height: 44)
    }

    /// Pulls the value onto its identity as the knob passes it and taps out a
    /// selection haptic on the way in, so getting a slider back to 0 mid-drag
    /// takes no precision and is felt rather than read.
    private func detented(_ value: Double, trackWidth: CGFloat) -> Double {
        let identity = PhotoAdjustments()[kind]
        let result = EditorLayoutMetrics.snapped(
            value,
            detent: identity,
            range: range,
            trackWidth: trackWidth
        )
        let isOnDetent = result == identity
        if isOnDetent, !isHoldingDetent {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        isHoldingDetent = isOnDetent
        return result
    }

    private var troughFill: LinearGradient {
        LinearGradient(
            colors: [EditorTheme.sliderTrack, EditorTheme.sliderTrack],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var normalizedFraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    @ViewBuilder
    private func fill(width: CGFloat, fraction: CGFloat) -> some View {
        if EditorTheme.troughGradient(for: kind) == nil {
            let center: CGFloat = 0.5
            if isBipolar {
                let start = min(fraction, center)
                let end = max(fraction, center)
                Capsule()
                    .fill(EditorTheme.accent)
                    .frame(width: max(0, (end - start) * width), height: isActive ? 4 : 3)
                    .offset(x: start * width)
            } else {
                Capsule()
                    .fill(EditorTheme.accent)
                    .frame(width: max(0, fraction * width), height: isActive ? 4 : 3)
            }
        }
    }
}

/// Horizontal-only pan over a slider track.
///
/// `HorizontalPanGestureRecognizer` fails itself as soon as the first 10pt of
/// travel look vertical, which leaves the enclosing scroll view in charge. When
/// it does win, it disables the scroll view's own pan for the duration of the
/// touch, so the panel cannot scroll and drag a value at the same time.
struct SliderPanCatcher: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let recognizer = HorizontalPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        // One finger only, so a two-finger pinch on the photo or a two-finger
        // scroll never reads as a slider drag.
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        private weak var suspendedScrollView: UIScrollView?

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat) -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handle(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view).x
            switch recognizer.state {
            case .began:
                suspendScrolling(from: view)
                onBegan()
                onChanged(translation)
            case .changed:
                onChanged(translation)
            case .ended, .cancelled, .failed:
                resumeScrolling()
                onEnded(translation)
            default:
                break
            }
        }

        private func suspendScrolling(from view: UIView) {
            var candidate: UIView? = view.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    scrollView.panGestureRecognizer.isEnabled = false
                    suspendedScrollView = scrollView
                    return
                }
                candidate = current.superview
            }
        }

        private func resumeScrolling() {
            suspendedScrollView?.panGestureRecognizer.isEnabled = true
            suspendedScrollView = nil
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    private var hasDecidedAxis = false
    private var startLocation = CGPoint.zero

    override func reset() {
        super.reset()
        hasDecidedAxis = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first, let view {
            startLocation = touch.location(in: view)
        }
    }

    /// The direction test runs *before* `super`, off the raw touch location
    /// rather than `translation(in:)`.
    ///
    /// `UIPanGestureRecognizer` begins on its own after roughly 10pt, and once it
    /// begins the row disables the scroll view's pan — so deciding after `super`
    /// meant a vertical flick could be claimed by the slider in the same frame it
    /// was rejected, which is what made the middle of the panel hard to scroll.
    /// Arbitrating at 8pt guarantees the verdict lands first.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !hasDecidedAxis, let view, let touch = touches.first {
            let current = touch.location(in: view)
            let dx = current.x - startLocation.x
            let dy = current.y - startLocation.y
            if hypot(dx, dy) >= EditorLayoutMetrics.gestureArbitrationDistance {
                hasDecidedAxis = true
                // A slider only wins a pan that is genuinely horizontal — within
                // 25° of the axis. Anything more diagonal is the scroll view's.
                if !EditorLayoutMetrics.isHorizontalPan(dx: dx, dy: dy) {
                    state = .failed
                    return
                }
            }
        }
        super.touchesMoved(touches, with: event)
    }
}
