import SwiftUI

/// The histogram, as a glass card floating over the photo instead of a fixed
/// strip that costs the image height. It can be dragged to any of the four
/// corners and collapsed to the action-bar pill. It always reads the whole photo:
/// not the part currently on screen, and not the selected mask — a readout that
/// changes meaning when a mask is opened cannot be used to judge the frame's
/// exposure.
struct EditorHistogramCard: View {
    let histogram: PhotoHistogram
    @Bindable var chrome: EditorChromeModel
    /// Image area the card is allowed to sit in, in the stage's coordinates.
    let bounds: CGRect
    /// Shared with the collapsed pill in the action bar, so collapsing animates as
    /// one object shrinking into the chrome rather than two views cross-fading.
    let namespace: Namespace.ID

    private var size: CGSize {
        EditorLayoutMetrics.histogramSize(collapsed: false)
    }

    private var restingCenter: CGPoint {
        EditorLayoutMetrics.histogramCenter(
            for: chrome.histogramCorner,
            cardSize: size,
            in: bounds
        )
    }

    private var center: CGPoint {
        guard let offset = chrome.histogramDragOffset else { return restingCenter }
        return CGPoint(
            x: restingCenter.x + offset.width,
            y: restingCenter.y + offset.height
        )
    }

    var body: some View {
        card
            .matchedGeometryEffect(id: EditorHistogramTransition.id, in: namespace)
            .frame(width: size.width, height: size.height)
            .position(center)
            .gesture(dragGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("RGB histogram")
            .accessibilityValue(accessibilitySummary)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            plot
                .frame(height: 46)
                .padding(.horizontal, 9)
            scaleRow
        }
        // Deliberately lighter glass than the rest of the chrome: the card sits on
        // top of the photo the whole time, so the picture has to stay readable
        // through it.
        .editorGlass(
            cornerRadius: 14,
            tint: EditorTheme.glassLight,
            materialOpacity: 0.45
        )
        // A tap anywhere on the card also parks it — the close button is there to
        // say that parking is possible, not to be the only way to do it.
        .onTapGesture(perform: collapse)
    }

    private func collapse() {
        withAnimation(EditorHistogramTransition.animation) {
            chrome.collapseHistogram()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 3, height: 3)
                }
            }
            Text("RGB")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer(minLength: 0)
            if histogram.hasClippedHighlights {
                Circle()
                    .fill(EditorTheme.clipping)
                    .frame(width: 6, height: 6)
                    .shadow(color: EditorTheme.clipping, radius: 4)
                    .accessibilityHidden(true)
            }
            closeButton
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 24)
    }

    /// Visible affordance for parking the card. Tapping the card anywhere does the
    /// same thing, but without a close mark nothing tells the user the card can be
    /// got rid of, so it reads as permanent furniture sitting on the photo.
    private var closeButton: some View {
        Button(action: collapse) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse histogram")
    }

    private var plot: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.06))

                toneGrid(size: proxy.size)

                area(histogram.luminance, size: proxy.size)
                    .fill(Color.white.opacity(0.28))

                line(histogram.red, size: proxy.size)
                    .stroke(EditorTheme.histogramRed.opacity(0.8), lineWidth: 1.4)
                    .blendMode(.screen)
                line(histogram.green, size: proxy.size)
                    .stroke(EditorTheme.histogramGreen.opacity(0.8), lineWidth: 1.4)
                    .blendMode(.screen)
                line(histogram.blue, size: proxy.size)
                    .stroke(EditorTheme.histogramBlue.opacity(0.8), lineWidth: 1.4)
                    .blendMode(.screen)

                if histogram.hasClippedHighlights {
                    HStack {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(EditorTheme.clipping.opacity(0.18))
                            .frame(width: proxy.size.width * 0.12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .drawingGroup()
        }
    }

    private var scaleRow: some View {
        HStack {
            Text("0")
            Spacer(minLength: 0)
            Text("MID")
            Spacer(minLength: 0)
            Text("255")
        }
        .font(.system(size: 8))
        .foregroundStyle(Color.white.opacity(0.4))
        .padding(.horizontal, 10)
        .frame(height: 12)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                chrome.histogramDragOffset = value.translation
            }
            .onEnded { value in
                let dropped = CGPoint(
                    x: restingCenter.x + value.translation.width,
                    y: restingCenter.y + value.translation.height
                )
                let corner = EditorLayoutMetrics.nearestHistogramCorner(
                    to: dropped,
                    in: bounds
                )
                withAnimation(EditorTheme.panelSpring) {
                    chrome.histogramCorner = corner
                    chrome.histogramDragOffset = nil
                }
            }
    }

    private func toneGrid(size: CGSize) -> some View {
        Path { path in
            for fraction in [0.25, 0.5, 0.75] {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
    }

    private func line(_ values: [Double], size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * CGFloat(1 - min(1, max(0, value)))
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func area(_ values: [Double], size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, value) in values.enumerated() {
                path.addLine(
                    to: CGPoint(
                        x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: size.height * CGFloat(1 - min(1, max(0, value)))
                    )
                )
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private var accessibilitySummary: String {
        let values = histogram.luminance
        guard values.count > 1,
              let peak = values.indices.max(by: { values[$0] < values[$1] })
        else { return "Histogram is loading" }
        let position = Double(peak) / Double(values.count - 1)
        let clipping = histogram.hasClippedHighlights ? ", highlights clipped" : ""
        if position < 0.33 { return "Peak is in the shadows" + clipping }
        if position < 0.67 { return "Peak is in the midtones" + clipping }
        return "Peak is in the highlights" + clipping
    }
}

enum EditorHistogramTransition {
    static let id = "shotdex.edit.histogram"
    /// Slow enough to read as the card travelling into the chrome, tight enough
    /// not to feel sluggish.
    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

/// The parked histogram: the action-bar mini, made tappable so it expands the
/// floating card. Shares the transition namespace so open/close reads as one
/// object growing out of / shrinking into the bar.
struct EditorHistogramPill: View {
    let histogram: PhotoHistogram
    let namespace: Namespace.ID
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            EditorHistogramSparkline(histogram: histogram)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                // Fills whatever the band frames it to — a flexible width running out
                // to the Dynamic Island, at the band buttons' full height.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .matchedGeometryEffect(id: EditorHistogramTransition.id, in: namespace)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("RGB histogram")
        .accessibilityHint("Tap to expand")
    }
}

struct EditorHistogramSparkline: View {
    let histogram: PhotoHistogram

    var body: some View {
        ZStack {
            EditorHistogramShape(values: histogram.luminance, isFilled: true)
                .fill(Color.white.opacity(0.32))
            EditorHistogramShape(values: histogram.red, isFilled: false)
                .stroke(EditorTheme.histogramRed.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
            EditorHistogramShape(values: histogram.green, isFilled: false)
                .stroke(EditorTheme.histogramGreen.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
            EditorHistogramShape(values: histogram.blue, isFilled: false)
                .stroke(EditorTheme.histogramBlue.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
        }
        .drawingGroup()
    }
}

/// One histogram trace as a `Shape`, so the card and the pill draw it the same
/// way at any size.
struct EditorHistogramShape: Shape {
    let values: [Double]
    let isFilled: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            if isFilled { path.move(to: CGPoint(x: 0, y: rect.height)) }
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.height * CGFloat(1 - min(1, max(0, value)))
                )
                if index == 0, !isFilled {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            if isFilled {
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.closeSubpath()
            }
        }
    }
}
