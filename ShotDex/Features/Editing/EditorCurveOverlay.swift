import SwiftUI
import ShotDexKit

/// The point tone curve, drawn over the photo while the Curve group is open —
/// Snapseed's model rather than a separate screen, so every drag is judged on the
/// picture it changes. A square plot centred on the image carries the photo's own
/// histogram behind the curve, a thirds grid, the identity diagonal, the live
/// curve and its draggable control points. Drag a point to move it (endpoints
/// slide along their edge, interior points stay between their neighbours); drag on
/// empty graph to drop a new point; double-tap a point to remove it. While a finger
/// is down the plot fades almost away — only the curve and the grabbed point stay
/// as a faint trace — so the photo behind it is what the eye reads; it comes back
/// the moment the finger lifts. The channel chips live in the panel below.
struct EditorCurveOverlay: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    /// Where the photo is laid out, in the stage's coordinates.
    let imageRect: CGRect
    /// The whole stage: the plot is sized to it and only centred on the photo.
    let stageRect: CGRect

    @State private var grabbed: Int?
    /// A finger is on the graph: the plot steps back so the photo shows through.
    @State private var isShaping = false

    private var channel: ToneCurveChannel { chrome.curveChannel }
    private var points: [CurvePoint] { controller.recipe.curve[channel] }

    /// Opacity of the chrome that is not being touched — scrim, grid, diagonal,
    /// histogram, the other points — while a drag is in progress.
    private static let restingChromeOpacity = 0.10
    /// Opacity the curve and the grabbed point keep while shaping: enough to know
    /// what is being pulled, not enough to hide the photo.
    private static let restingCurveOpacity = 0.45
    private static let fade = Animation.easeOut(duration: 0.15)

    private var chromeOpacity: Double { isShaping ? Self.restingChromeOpacity : 1 }
    private var curveOpacity: Double { isShaping ? Self.restingCurveOpacity : 1 }

    var body: some View {
        let rect = EditorLayoutMetrics.curvePlotRect(in: imageRect, stage: stageRect)
        let local = CGRect(origin: .zero, size: rect.size)
        ZStack {
            plotChrome(local)
                .opacity(chromeOpacity)
            curvePath(local)
                .stroke(
                    channelColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .opacity(curveOpacity)
            ForEach(points.indices, id: \.self) { index in
                controlPoint(isGrabbed: grabbed == index)
                    .position(viewPoint(points[index], in: local))
                    .opacity(grabbed == index ? curveOpacity : chromeOpacity)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        // A curve is grabbed at points a pointer cannot see. `.automatic`
        // gives the cursor the region to work in without lifting the canvas
        // off the photo behind it.
        .hoverEffect(.automatic)
        .highPriorityGesture(deleteGesture(local))
        .gesture(dragGesture(local))
        .animation(Self.fade, value: isShaping)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tone curve, \(channel.displayName) channel")
        .accessibilityHint("Drag on the graph to shape the curve")
    }

    // MARK: Layers

    private var channelColor: Color {
        switch channel {
        case .rgb: .white
        case .red: EditorTheme.histogramRed
        case .green: EditorTheme.histogramGreen
        case .blue: EditorTheme.histogramBlue
        }
    }

    /// Everything under the curve: a light scrim so the lines read on a bright
    /// photo, the histogram of the channel being shaped, the thirds grid and the
    /// identity diagonal.
    private func plotChrome(_ rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(Color.black.opacity(0.18))
            histogramArea(rect)
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            gridPath(rect).stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            Path {
                $0.move(to: CGPoint(x: 0, y: rect.height))
                $0.addLine(to: CGPoint(x: rect.width, y: 0))
            }
            .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    /// The photo's histogram, as Lightroom draws it behind its curve: the channel
    /// being shaped in its own colour, luminance for the RGB master. The card in the
    /// band keeps showing all three; here only the one the curve acts on matters.
    @ViewBuilder
    private func histogramArea(_ rect: CGRect) -> some View {
        let series = histogramSeries
        if series.values.count > 1 {
            areaPath(series.values, in: rect).fill(series.fill)
        }
    }

    private var histogramSeries: (values: [Double], fill: Color) {
        let histogram = controller.histogram
        switch channel {
        case .rgb:
            return (histogram.luminance, Color.white.opacity(0.22))
        case .red:
            return (histogram.red, EditorTheme.histogramRed.opacity(0.3))
        case .green:
            return (histogram.green, EditorTheme.histogramGreen.opacity(0.3))
        case .blue:
            return (histogram.blue, EditorTheme.histogramBlue.opacity(0.3))
        }
    }

    private func controlPoint(isGrabbed: Bool) -> some View {
        let diameter = EditorLayoutMetrics.curvePointDiameter
        return Circle()
            .fill(.white)
            .frame(width: diameter, height: diameter)
            .overlay { Circle().strokeBorder(channelColor, lineWidth: 2) }
            .shadow(color: .black.opacity(0.5), radius: 3)
            .scaleEffect(isGrabbed ? 1.25 : 1)
    }

    // MARK: Paths

    private func gridPath(_ rect: CGRect) -> Path {
        Path { path in
            for fraction in [1.0 / 3, 2.0 / 3] {
                let x = rect.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rect.height))
                let y = rect.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: rect.width, y: y))
            }
        }
    }

    private func curvePath(_ rect: CGRect) -> Path {
        let lut = ToneCurveMath.lut(points: points, count: 128)
        return Path { path in
            for (index, value) in lut.enumerated() {
                let x = rect.width * CGFloat(index) / CGFloat(lut.count - 1)
                let y = rect.height * (1 - CGFloat(value))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func areaPath(_ values: [Double], in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height))
            for (index, value) in values.enumerated() {
                path.addLine(
                    to: CGPoint(
                        x: rect.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: rect.height * CGFloat(1 - min(1, max(0, value)))
                    )
                )
            }
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }
    }

    // MARK: Gestures

    private func dragGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grabbed == nil {
                    isShaping = true
                    controller.beginContinuousChange()
                    if let index = nearestPointIndex(to: value.startLocation, in: rect) {
                        grabbed = index
                    } else {
                        var updated = points
                        let new = clamped(
                            index: nil,
                            to: curvePoint(value.location, in: rect),
                            in: updated
                        )
                        let insertion = updated.firstIndex { $0.x > new.x } ?? updated.count
                        updated.insert(new, at: insertion)
                        controller.setCurve(updated, for: channel)
                        grabbed = insertion
                    }
                }
                guard let index = grabbed, index < points.count else { return }
                var updated = points
                updated[index] = clamped(
                    index: index,
                    to: curvePoint(value.location, in: rect),
                    in: updated
                )
                controller.setCurve(updated, for: channel)
            }
            .onEnded { _ in
                controller.endContinuousChange()
                grabbed = nil
                isShaping = false
            }
    }

    private func deleteGesture(_ rect: CGRect) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard let index = nearestPointIndex(to: value.location, in: rect),
                      index != 0, index != points.count - 1
                else { return }
                controller.beginContinuousChange()
                var updated = points
                updated.remove(at: index)
                controller.setCurve(updated, for: channel)
                controller.endContinuousChange()
            }
    }

    // MARK: Geometry

    private func viewPoint(_ point: CurvePoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.maxY - CGFloat(point.y) * rect.height
        )
    }

    private func curvePoint(_ location: CGPoint, in rect: CGRect) -> CurvePoint {
        guard rect.width > 0, rect.height > 0 else { return CurvePoint(x: 0, y: 0) }
        return CurvePoint(
            x: min(1, max(0, Double((location.x - rect.minX) / rect.width))),
            y: min(1, max(0, Double((rect.maxY - location.y) / rect.height)))
        )
    }

    private func nearestPointIndex(to location: CGPoint, in rect: CGRect) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for index in points.indices {
            let view = viewPoint(points[index], in: rect)
            let distance = hypot(view.x - location.x, view.y - location.y)
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (index, distance)
            }
        }
        guard let best, best.distance <= EditorLayoutMetrics.curvePointHitRadius else {
            return nil
        }
        return best.index
    }

    /// Constrain a dragged/added point: endpoints keep their x on the edge, interior
    /// points stay strictly between their neighbours, everything clamps to 0…1 in y.
    private func clamped(index: Int?, to point: CurvePoint, in current: [CurvePoint]) -> CurvePoint {
        let y = min(1, max(0, point.y))
        guard let index else {
            // A new interior point: keep it off the very edges.
            return CurvePoint(x: min(0.99, max(0.01, point.x)), y: y)
        }
        if index == 0 { return CurvePoint(x: 0, y: y) }
        if index == current.count - 1 { return CurvePoint(x: 1, y: y) }
        let lower = current[index - 1].x + 0.001
        let upper = current[index + 1].x - 0.001
        return CurvePoint(x: min(upper, max(lower, point.x)), y: y)
    }
}

/// The Curve group's panel: channel chips (RGB master, Red, Green, Blue — a dot
/// marks a channel that is no longer the straight line), a Reset for the shown
/// channel, the how-to line, and a row of preset shapes for the shown channel.
/// The graph itself is on the photo.
struct EditorCurvePanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    private var channel: ToneCurveChannel { chrome.curveChannel }
    private var isLinear: Bool {
        controller.recipe.curve[channel] == ToneCurveAdjustments.linear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ToneCurveChannel.allCases) { option in
                    Button {
                        chrome.curveChannel = option
                    } label: {
                        HStack(spacing: 5) {
                            Text(option.displayName)
                            // Dirty marker on the *other* channels only: on the accent
                            // chip a dot is illegible, and Reset already says this one
                            // has a curve.
                            if channel != option,
                               controller.recipe.curve[option] != ToneCurveAdjustments.linear {
                                Circle()
                                    .fill(EditorTheme.accent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: channel == option))
                }
                Spacer(minLength: 0)
                Button("Reset") {
                    controller.resetCurve(channel)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isLinear ? EditorTheme.dimText : EditorTheme.accent)
                .disabled(isLinear)
            }

            Text("Drag to shape · drag on empty graph to add · double-tap a point to remove")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
                .fixedSize(horizontal: false, vertical: true)

            presetRow

            if chrome.isCurveGraphHidden {
                Button {
                    withAnimation(EditorTheme.animation) {
                        chrome.isCurveGraphHidden = false
                    }
                } label: {
                    Label("Show Graph", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Starting shapes for the shown channel. The chip whose points the channel
    /// currently matches is lit; dragging any point unlights it.
    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ToneCurveAdjustments.presets) { preset in
                    Button(preset.name) {
                        controller.applyCurvePreset(preset, to: channel)
                    }
                    .buttonStyle(EditorChipButtonStyle(
                        isSelected: controller.recipe.curve[channel] == preset.points
                    ))
                }
            }
        }
        // Bleed the scroll to the panel edges so the row does not clip mid-chip.
        .padding(.horizontal, -14)
        .contentMargins(.horizontal, 14, for: .scrollContent)
    }
}
