import SwiftUI
import UIKit

/// The grading tint wheel: hue is the angle, saturation the distance from the
/// center, center = no tint. Absolute positioning — the knob jumps to the
/// finger — because a wheel dragged by relative translation feels detached.
struct EditorColorWheel: View {
    /// 0…1.
    let hue: Double
    /// 0…1; 0 parks the knob at the center.
    let saturation: Double
    var diameter: CGFloat = 168
    let onBegin: () -> Void
    let onChange: (_ hue: Double, _ saturation: Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    @State private var isHoldingCenter = false

    var body: some View {
        let radius = diameter / 2
        ZStack {
            // SwiftUI's flipped y makes atan2 and AngularGradient agree with no
            // sign fixups: both sweep clockwise-on-screen from the 3-o'clock axis.
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: stride(from: 0.0, through: 360, by: 30).map {
                        Color(hue: $0 / 360, saturation: 1, brightness: 1)
                    }),
                    center: .center
                ))
            // Gray core rather than white so the desaturated middle keeps the
            // panel's brightness instead of glowing.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(white: 0.5), Color(white: 0.5).opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                ))
            Circle()
                .strokeBorder(EditorTheme.hairline, lineWidth: 1)
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 3, height: 3)
            knob(radius: radius)
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            WheelPanCatcher { location in
                handleTouch(location, radius: radius, isFirst: true)
            } onChanged: { location in
                handleTouch(location, radius: radius, isFirst: false)
            } onEnded: {
                isHoldingCenter = false
                onEnd()
            }
        }
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            onReset()
        }
        .accessibilityElement()
        .accessibilityLabel("Tint wheel")
        .accessibilityValue(
            "Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent"
        )
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 10.0 : -10.0
            var degrees = (hue * 360 + step).truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            onBegin()
            onChange(degrees / 360, max(saturation, 0.05))
            onEnd()
        }
    }

    private func knob(radius: CGFloat) -> some View {
        let angle = hue * 2 * .pi
        let distance = CGFloat(saturation) * radius
        return Circle()
            .fill(.white)
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            .overlay {
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .frame(width: 12, height: 12)
            }
            .offset(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
    }

    private func handleTouch(_ location: CGPoint, radius: CGFloat, isFirst: Bool) {
        let dx = location.x - radius
        let dy = location.y - radius
        let distance = hypot(dx, dy)

        if isFirst { onBegin() }

        // Center detent: "no tint" is reachable without pixel-hunting.
        if distance < 8 {
            if !isHoldingCenter {
                UISelectionFeedbackGenerator().selectionChanged()
                isHoldingCenter = true
            }
            onChange(hue, 0)
            return
        }
        isHoldingCenter = false

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        onChange(Double(degrees) / 360, Double(min(1, distance / radius)))
    }
}

/// The wheel claims every one-finger pan that starts on the disc — no axis
/// test, unlike `SliderPanCatcher` — and suspends the enclosing scroll view
/// for the duration. A plain `DragGesture` inside a `ScrollView` loses
/// vertical drags to the scroll, which is exactly the wrong owner here.
private struct WheelPanCatcher: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
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
        var onBegan: (CGPoint) -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: () -> Void
        private weak var suspendedScrollView: UIScrollView?

        init(
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handle(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            switch recognizer.state {
            case .began:
                suspendScrolling(from: view)
                onBegan(location)
            case .changed:
                onChanged(location)
            case .ended, .cancelled, .failed:
                resumeScrolling()
                onEnded()
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
