import SwiftUI
import UIKit
import ShotDexKit

/// The one slider used everywhere in the editor.
///
/// Light / Color / Effects / Detail rows, the colour mixer, grading, point colour,
/// crop straighten — all render through this, so the whole look (white cursor bar,
/// accent fill, colour tracks, the zero notch) and the whole-row gesture (drag
/// anywhere, 300ms-hold fine mode, vertical-pan scrolls, double-tap reset, long-
/// press the value for the keypad) live in exactly one place. Callers pass data
/// and a few switches; nobody re-implements the style. There is no round knob and
/// no system `Slider`.
///
/// - `range` sets min/max. `anchor` is where the accent fill starts and the notch
///   sits — the centre for a two-way row, the left end for a one-way one.
///   `showsAnchorNotch` draws that centre notch. `detent` is an optional value the
///   cursor snaps onto as it passes (0, or 100% for a filter amount). A
///   `trackGradient` makes the track carry its own colour and suppresses the
///   accent fill — the colour is the meaning.
struct EditorValueSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    var isActive = false
    var anchor: Double = 0
    var showsAnchorNotch = false
    var detent: Double?
    var trackGradient: LinearGradient?
    /// Draw a thin white trail from the anchor to the cursor even though the
    /// track carries a gradient — for ramps that are not neutral where the
    /// anchor is. See `EditorTheme.troughIsNeutralAtAnchor`.
    var showsTrailOverGradient = false
    /// Overrides the spoken accessibility name; defaults to `label` (which is often
    /// an abbreviation like "TEMP").
    var accessibilityName: String?
    let onBeginDrag: () -> Void
    let onDrag: (Double) -> Void
    var onEndDrag: (Double, Double, Bool) -> Void = { _, _, _ in }
    let onReset: () -> Void
    var onEditValue: (() -> Void)?

    @State private var dragStartValue = 0.0
    @State private var dragStartDate = Date()
    @State private var hasActivated = false
    @State private var isHoldingDetent = false
    @State private var trackWidth: CGFloat = 1
    @Environment(\.editorSliderStacked) private var isStacked

    var body: some View {
        Group {
            if isStacked { stackedRow } else { inlineRow }
        }
        .background(isActive ? Color.white.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .overlay { gestureCatcher }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityName ?? label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 40
            let next = direction == .increment ? value + step : value - step
            let clamped = min(range.upperBound, max(range.lowerBound, next))
            onDrag(clamped)
            onEndDrag(value, clamped, false)
        }
    }

    /// Phone: name, track and number on one 34pt line.
    private var inlineRow: some View {
        HStack(spacing: 8) {
            nameText
                .frame(width: EditorLayoutMetrics.editorRowLabelWidth, alignment: .leading)

            track

            valueTextView
                .frame(width: EditorLayoutMetrics.editorRowValueWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: EditorLayoutMetrics.editorRowHeight)
    }

    /// Wide sidebar: name and number on the first line, the track full width
    /// underneath. The name is no longer upper-cased and no longer clipped to
    /// 88pt — there is room for "Saturation" to be written out.
    private var stackedRow: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                nameText
                Spacer(minLength: 8)
                valueTextView
            }
            track
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.sidebarSliderRowHeight)
    }

    private var nameText: some View {
        Text(isStacked ? label : label.uppercased())
            .font(
                isStacked
                    ? .system(size: 12, weight: .regular)
                    : .system(size: 10.5, weight: .semibold)
            )
            .tracking(isStacked ? 0 : 0.5)
            .foregroundStyle(isActive ? .white : EditorTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var valueTextView: some View {
        Text(valueText)
            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(isActive ? EditorTheme.accent : Color.white.opacity(0.85))
            .lineLimit(1)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let frac = fraction(of: value)
            let anchorFrac = fraction(of: anchor)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackGradient ?? neutralTrack)
                    .frame(height: trackGradient == nil ? 4 : 6)

                if trackGradient == nil {
                    accentFill(width: width, fraction: frac, anchor: anchorFrac)
                } else if showsTrailOverGradient {
                    gradientTrail(width: width, fraction: frac, anchor: anchorFrac)
                }

                if showsAnchorNotch {
                    Rectangle()
                        .fill(Color.black.opacity(trackGradient == nil ? 0.62 : 0.55))
                        .frame(width: 1, height: trackGradient == nil ? 8 : 10)
                        .offset(x: anchorFrac * width - 0.5)
                }

                cursor
                    .offset(x: min(width - 4, max(0, frac * width - 2)))
            }
            .frame(maxHeight: .infinity)
            .onAppear { trackWidth = max(1, width) }
            .onChange(of: width) { trackWidth = max(1, $0) }
        }
        // Inline, the track is the row and takes its whole height so a drag can
        // start anywhere on it. Stacked, the label line above already owns
        // 18pt, so the track keeps only what is left.
        .frame(height: isStacked ? 20 : EditorLayoutMetrics.editorRowHeight)
    }

    private var cursor: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(.white)
            .frame(width: 4, height: 14)
            .modifier(CursorGlow(isColored: trackGradient != nil))
    }

    private var gestureCatcher: some View {
        EditorRowGestureCatcher(
            valueColumnWidth: EditorLayoutMetrics.editorRowValueWidth + 14,
            // Stacked, the value is on the first line and the **track runs the
            // full width underneath it**, so an x-only test hands the trailing
            // 54pt of the row — the top 13% of every parameter's range — to the
            // keypad. The same press is how fine mode is armed, and the long
            // press wins outright. So the keypad's region is the label line
            // only; inline it stays the whole row height, where the value
            // really is a column beside the track.
            valueRowHeight: isStacked ? 18 : nil,
            onBegan: {
                dragStartValue = value
                dragStartDate = Date()
                hasActivated = false
                isHoldingDetent = detent.map { abs(value - $0) < 0.0001 } ?? false
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
                    snapped(
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
            onEditValue: onEditValue ?? {}
        )
        // Right-click on a trackpad, long-press on a finger: the two things a
        // desktop editor puts on a slider, and until now the only way to either
        // was a gesture nobody can see (double tap resets, two-finger tap types
        // a value).
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onReset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            if let onEditValue {
                Button(action: onEditValue) {
                    Label("Enter Value…", systemImage: "keyboard")
                }
            }
        }
        .hoverEffect(.highlight)
    }

    /// Pulls the value onto `detent` as the cursor passes it and taps out a
    /// selection haptic on the way in, so getting a row back to its rest point
    /// takes no precision and is felt rather than read.
    private func snapped(_ value: Double, trackWidth: CGFloat) -> Double {
        guard let detent else { return value }
        let result = EditorLayoutMetrics.snapped(
            value,
            detent: detent,
            range: range,
            trackWidth: trackWidth
        )
        let isOnDetent = result == detent
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

    private func fraction(of raw: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((raw - range.lowerBound) / span)
    }

    /// White, not accent, and thinner than the ramp it sits on: it has to read
    /// as a measurement over the colour rather than as another colour.
    @ViewBuilder
    private func gradientTrail(width: CGFloat, fraction: CGFloat, anchor: CGFloat) -> some View {
        let start = min(fraction, anchor)
        let end = max(fraction, anchor)
        Capsule()
            .fill(.white)
            .frame(width: max(0, (end - start) * width), height: 2)
            .offset(x: start * width)
            .shadow(color: .black.opacity(0.5), radius: 1)
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

/// The catalog-driven wrapper for a `PhotoAdjustmentKind` row: it reads the kind's
/// range, identity, bipolarity, colour track, and formatted value, then hands them
/// to the one `EditorValueSlider`.
struct EditorSliderRow: View {
    let kind: PhotoAdjustmentKind
    let value: Double
    let isActive: Bool
    let onBeginDrag: () -> Void
    let onDrag: (Double) -> Void
    let onEndDrag: (Double, Double, Bool) -> Void
    let onReset: () -> Void
    let onEditValue: () -> Void

    var body: some View {
        let identity = PhotoAdjustments()[kind]
        EditorValueSlider(
            label: EditorAdjustmentCatalog.shortTitle(of: kind),
            value: value,
            range: EditorAdjustmentCatalog.sliderRange(of: kind),
            valueText: EditorAdjustmentCatalog.displayText(value, of: kind),
            isActive: isActive,
            anchor: identity,
            showsAnchorNotch: EditorAdjustmentCatalog.isBipolar(kind),
            detent: identity,
            trackGradient: EditorTheme.troughGradient(for: kind),
            showsTrailOverGradient: !EditorTheme.troughIsNeutralAtAnchor(for: kind),
            accessibilityName: kind.displayName,
            onBeginDrag: onBeginDrag,
            onDrag: onDrag,
            onEndDrag: onEndDrag,
            onReset: onReset,
            onEditValue: onEditValue
        )
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
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
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
    /// Height of the band, measured from the row's top, in which a long press
    /// counts as "on the value". Nil means the whole row — the inline layout,
    /// where the value column spans it.
    var valueRowHeight: CGFloat?
    let onBegan: () -> Void
    let onChanged: (CGFloat, Bool) -> Void
    let onEnded: () -> Void
    let onReset: () -> Void
    let onEditValue: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            valueColumnWidth: valueColumnWidth,
            valueRowHeight: valueRowHeight,
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
        context.coordinator.valueRowHeight = valueRowHeight
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onReset = onReset
        context.coordinator.onEditValue = onEditValue
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var valueColumnWidth: CGFloat
        var valueRowHeight: CGFloat?
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
            valueRowHeight: CGFloat?,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat, Bool) -> Void,
            onEnded: @escaping () -> Void,
            onReset: @escaping () -> Void,
            onEditValue: @escaping () -> Void
        ) {
            self.valueColumnWidth = valueColumnWidth
            self.valueRowHeight = valueRowHeight
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
            let point = recognizer.location(in: view)
            guard point.x >= view.bounds.width - valueColumnWidth else { return }
            if let valueRowHeight, point.y > valueRowHeight { return }
            onEditValue()
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

/// A two-finger tap anywhere on the photo, which is how Lightroom and Procreate
/// both spell Undo.
///
/// It exists because on a phone the undo disc is in the band's top-left corner —
/// the one place a right thumb cannot reach without regripping — while the whole
/// working surface (panel, wheel, Save) is glued to the bottom 246pt, and the
/// only other route was ⌘Z on a keyboard the phone does not have.
///
/// The recogniser is installed on the **superview**, not on this zero-sized view,
/// because a `.background` view that swallowed touches would take them from the
/// stage. `cancelsTouchesInView = false` and simultaneous recognition keep every
/// other gesture — pinch, pan, the hold-to-compare, the paint layer — working
/// exactly as before; a two-finger *tap* needs both touches down and up in place,
/// so a pinch (which moves) never satisfies it.
struct EditorTwoFingerTapCatcher: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.attach(from: view)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        private weak var host: UIView?
        private var recognizer: UITapGestureRecognizer?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        /// Installs on the editor's own hosting view — the top of the chain
        /// below the window — rather than on this zero-sized carrier or its
        /// immediate parent, either of which can be laid out to nothing.
        ///
        /// That means the tap is live over the panel as well as the photo,
        /// which is what Procreate does and is the point: undo should not
        /// depend on where the hand happens to be. It retries because a
        /// representable's view is not in the hierarchy when `makeUIView`
        /// returns, and one run-loop hop is not always enough.
        func attach(from view: UIView, attempt: Int = 0) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let host = Self.hostingAncestor(of: view) else {
                    guard attempt < 5 else { return }
                    self.attach(from: view, attempt: attempt + 1)
                    return
                }
                let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
                tap.numberOfTouchesRequired = 2
                tap.numberOfTapsRequired = 1
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = self
                host.addGestureRecognizer(tap)
                self.host = host
                self.recognizer = tap
            }
        }

        private static func hostingAncestor(of view: UIView) -> UIView? {
            var candidate: UIView? = view.superview
            var best: UIView?
            while let current = candidate, !(current is UIWindow) {
                best = current
                candidate = current.superview
            }
            return best
        }

        func detach() {
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
        }

        @objc private func handleTap() {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
