import SwiftUI
import UIKit

/// One "28c" parameter row: `[label 88][track][value 40]`, 34pt tall.
///
/// The whole row is one horizontal-drag surface — a pan that starts on the label,
/// the track or the value all set the value (`delta = translation.x / trackWidth *
/// range`). Press in place for 300ms first and the drag switches to fine mode
/// (quarter rate). A vertical pan anywhere on the row scrolls the list instead. A
/// double tap resets the row; a long press on the value column opens the numeric
/// keypad. There is no round knob and no system `Slider`: the value is a white
/// bar, the pushed range an accent bar with a glow, and a track that already
/// carries a colour (Temp, Tint) is never tinted accent on top.
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
    @State private var trackWidth: CGFloat = 1

    private var range: ClosedRange<Double> { EditorAdjustmentCatalog.sliderRange(of: kind) }
    private var isBipolar: Bool { EditorAdjustmentCatalog.isBipolar(kind) }
    private var identity: Double { PhotoAdjustments()[kind] }
    private var isZero: Bool { abs(value - identity) < 0.0001 }
    private var coloredGradient: LinearGradient? { EditorTheme.troughGradient(for: kind) }

    var body: some View {
        HStack(spacing: 10) {
            Text(EditorAdjustmentCatalog.shortTitle(of: kind).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(isActive ? .white : EditorTheme.secondaryText)
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.editorRowLabelWidth, alignment: .leading)

            track

            Text(EditorAdjustmentCatalog.displayText(value, of: kind))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(isActive ? EditorTheme.accent : Color.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.editorRowValueWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: EditorLayoutMetrics.editorRowHeight)
        .background(isActive ? Color.white.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .overlay { gestureCatcher }
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
            let anchor = anchorFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(coloredGradient ?? neutralTrack)
                    .frame(height: coloredGradient == nil ? 4 : 6)

                if coloredGradient == nil {
                    accentFill(width: width, fraction: fraction, anchor: anchor)
                }

                // Zero mark: bipolar rows only. A one-way row (Grain, Feather…) has
                // no meaningful centre, so it gets none.
                if isBipolar {
                    Rectangle()
                        .fill(Color.black.opacity(coloredGradient == nil ? 0.62 : 0.55))
                        .frame(width: 1, height: coloredGradient == nil ? 8 : 10)
                        .offset(x: anchor * width - 0.5)
                }

                cursor
                    .offset(x: min(width - 4, max(0, fraction * width - 2)))
            }
            .frame(maxHeight: .infinity)
            .onAppear { trackWidth = max(1, width) }
            .onChange(of: width) { trackWidth = max(1, $0) }
        }
        .frame(height: EditorLayoutMetrics.editorRowHeight)
    }

    private var cursor: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: 4, height: 14)
            .modifier(CursorGlow(isColored: coloredGradient != nil))
    }

    private var gestureCatcher: some View {
        EditorRowGestureCatcher(
            valueColumnWidth: EditorLayoutMetrics.editorRowValueWidth + 14,
            onBegan: {
                dragStartValue = value
                dragStartDate = Date()
                hasActivated = false
                isHoldingDetent = isZero
                onBeginDrag()
            },
            onChanged: { translation, isFine in
                guard trackWidth > 0 else { return }
                guard abs(translation) >= EditorLayoutMetrics.sliderActivationDistance
                else { return }
                hasActivated = true
                let span = range.upperBound - range.lowerBound
                let gain = isFine ? EditorLayoutMetrics.sliderFineGain : 1
                let proposed = dragStartValue
                    + Double(translation / trackWidth) * span * gain
                onDrag(
                    detented(
                        min(range.upperBound, max(range.lowerBound, proposed)),
                        trackWidth: trackWidth
                    )
                )
            },
            onEnded: {
                let wasQuick = Date().timeIntervalSince(dragStartDate) < 0.25
                onEndDrag(dragStartValue, value, hasActivated && wasQuick)
                hasActivated = false
            },
            onReset: {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onReset()
            },
            onEditValue: onEditValue
        )
    }

    /// Pulls the value onto its identity as the cursor passes it and taps out a
    /// selection haptic on the way in, so getting a row back to 0 takes no
    /// precision and is felt rather than read.
    private func detented(_ value: Double, trackWidth: CGFloat) -> Double {
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

    private var neutralTrack: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.14)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var normalizedFraction: CGFloat {
        fraction(of: value)
    }

    /// Where the accent fill and the zero mark are anchored: the identity value.
    /// For a bipolar row that is the centre; for a one-way row it is the left end.
    private var anchorFraction: CGFloat {
        fraction(of: identity)
    }

    private func fraction(of raw: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((raw - range.lowerBound) / span)
    }

    @ViewBuilder
    private func accentFill(width: CGFloat, fraction: CGFloat, anchor: CGFloat) -> some View {
        let start = min(fraction, anchor)
        let end = max(fraction, anchor)
        Capsule()
            .fill(EditorTheme.accent)
            .frame(width: max(0, (end - start) * width), height: 4)
            .offset(x: start * width)
            .shadow(color: EditorTheme.accent.opacity(0.65), radius: 5)
    }
}

/// The cursor's glow. On a neutral track it is a soft white halo; on a coloured
/// track the white bar instead gets a dark hairline and drop shadow so it stays
/// legible over any hue it sits on.
private struct CursorGlow: ViewModifier {
    let isColored: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isColored {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        } else {
            content.shadow(color: .white.opacity(0.75), radius: 4)
        }
    }
}

/// The whole-row gesture surface for a `EditorSliderRow`.
///
/// One `UIView` carries every gesture the row needs so they never fight a SwiftUI
/// tap layered on top:
/// - a horizontal pan sets the value (vertical pans fail so the list scrolls);
/// - holding still for `sliderFineHoldSeconds` before moving switches the pan to
///   fine mode, reported through `onChanged`'s `isFine` flag;
/// - a double tap resets the row;
/// - a long press that lands in the value column opens the numeric keypad.
struct EditorRowGestureCatcher: UIViewRepresentable {
    let valueColumnWidth: CGFloat
    let onBegan: () -> Void
    let onChanged: (CGFloat, Bool) -> Void
    let onEnded: () -> Void
    let onReset: () -> Void
    let onEditValue: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            valueColumnWidth: valueColumnWidth,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onReset: onReset,
            onEditValue: onEditValue
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = HorizontalPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.valueColumnWidth = valueColumnWidth
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onReset = onReset
        context.coordinator.onEditValue = onEditValue
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var valueColumnWidth: CGFloat
        var onBegan: () -> Void
        var onChanged: (CGFloat, Bool) -> Void
        var onEnded: () -> Void
        var onReset: () -> Void
        var onEditValue: () -> Void

        private weak var suspendedScrollView: UIScrollView?
        private var beganDate = Date()
        private var isFine = false
        private var decidedFine = false

        init(
            valueColumnWidth: CGFloat,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat, Bool) -> Void,
            onEnded: @escaping () -> Void,
            onReset: @escaping () -> Void,
            onEditValue: @escaping () -> Void
        ) {
            self.valueColumnWidth = valueColumnWidth
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onReset = onReset
            self.onEditValue = onEditValue
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view).x
            switch recognizer.state {
            case .began:
                suspendScrolling(from: view)
                beganDate = Date()
                isFine = false
                decidedFine = false
                onBegan()
                onChanged(translation, false)
            case .changed:
                if !decidedFine,
                   abs(translation) >= EditorLayoutMetrics.sliderActivationDistance {
                    decidedFine = true
                    isFine = Date().timeIntervalSince(beganDate)
                        > EditorLayoutMetrics.sliderFineHoldSeconds
                }
                onChanged(translation, isFine)
            case .ended, .cancelled, .failed:
                resumeScrolling()
                onEnded()
            default:
                break
            }
        }

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            onReset()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            let x = recognizer.location(in: view).x
            if x >= view.bounds.width - valueColumnWidth {
                onEditValue()
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
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // The pan owns the value and must never run alongside the taps.
            false
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
