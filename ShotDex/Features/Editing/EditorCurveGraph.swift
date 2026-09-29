import SwiftUI
import ShotDexKit

/// The point tone curve as a square plot inside the panel (FS-03.13b §2) —
/// never over the photo, at any layout, so every drag is judged on a picture
/// nothing covers. The plot carries the photo's own histogram behind the
/// curve, a thirds grid, the identity diagonal, the live curve and its
/// draggable control points. Drag a point to move it (endpoints slide along
/// their edge, interior points stay between their neighbours); tap empty graph
/// to drop a new point; double-tap a point to remove it. It fills whatever
/// square it is given: 220×220 in the phone's Curve tool, the sidebar's width
/// on a wide screen.
///
/// A drag only shapes when it starts **on a control point**, and a new point
/// comes from an explicit tap: on the phone the panel around it is Curve's own,
/// but in the sidebar it sits inside a `ScrollView`, and a plot that claimed
/// every drag inserted a point on the first change event — before any
/// arbitration — so scrolling past the Curve section changed the photo's
/// contrast.
struct EditorCurveGraph: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    @State private var grabbed: Int?

    private var channel: ToneCurveChannel { chrome.curveChannel }
    private var points: [CurvePoint] { controller.editedCurve[channel] }
    /// Region mode draws the whole curve that is applied and has nothing to grab.
    private var showsRegion: Bool { chrome.curveMode == .region }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            plot(CGRect(origin: .zero, size: CGSize(width: side, height: side)))
                // On the plot, not the GeometryReader: there the element
                // came out empty and VoiceOver skipped the graph.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tone curve, \(channel.displayName) channel")
                .accessibilityValue(accessibilityPoints)
                .accessibilityHint("Tap the line to add a point. Drag to move it, double-tap to remove it.")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func plot(_ local: CGRect) -> some View {
        ZStack {
            plotChrome(local)
            curvePath(local)
                .stroke(
                    channelColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .black.opacity(0.6), radius: 1.5)
            if !showsRegion {
                ForEach(points.indices, id: \.self) { index in
                    controlPoint(isGrabbed: grabbed == index)
                        .position(viewPoint(points[index], in: local))
                }
            }
        }
        .allowsHitTesting(!showsRegion)
        .frame(width: local.width, height: local.height)
        .contentShape(Rectangle())
        // A curve is grabbed at points a pointer cannot see. `.automatic`
        // gives the cursor the region to work in.
        .hoverEffect(.automatic)
        .highPriorityGesture(deleteGesture(local))
        .gesture(insertGesture(local))
        .gesture(dragGesture(local))
    }

    /// "4 points" — what VoiceOver can say about a shape it cannot see.
    private var accessibilityPoints: String {
        showsRegion ? "Region curve" : "\(points.count) points"
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
        let lut = showsRegion
            ? ParametricCurveMath.combinedLUT(region: controller.editedCurve.region, points: controller.editedCurve.rgb, count: 128)
            : ToneCurveMath.lut(points: points, count: 128)
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

    /// Drag to shape — only a drag that starts on a control point (see the
    /// type's comment). Claiming the touch sets `activePlainSliderID`, which is
    /// what the sidebar's `.scrollDisabled` reads, so once shaping starts the
    /// list holds still.
    private func dragGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grabbed == nil {
                    guard let index = nearestPointIndex(to: value.startLocation, in: rect) else { return }
                    claimScroll()
                    controller.beginContinuousChange()
                    grabbed = index
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
                guard grabbed != nil else { return }
                controller.endContinuousChange()
                grabbed = nil
                releaseScroll()
            }
    }

    /// A tap on empty graph drops a point **on the line** at the tap's input
    /// level, as Lightroom does — the shape does not jump until it is dragged.
    private func insertGesture(_ rect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard nearestPointIndex(to: value.location, in: rect) == nil else { return }
                controller.beginContinuousChange()
                controller.setCurve(Self.inserting(at: curvePoint(value.location, in: rect).x, into: points), for: channel)
                controller.endContinuousChange()
            }
    }

    /// `points` with one more, at input `x` and the curve's own output there.
    static func inserting(at x: Double, into points: [CurvePoint]) -> [CurvePoint] {
        let x = min(0.99, max(0.01, x))
        let lut = ToneCurveMath.lut(points: points, count: 256)
        let y = Double(lut[Int((x * 255).rounded())])
        var updated = points
        let insertion = updated.firstIndex { $0.x > x } ?? updated.count
        updated.insert(CurvePoint(x: x, y: min(1, max(0, y))), at: insertion)
        return updated
    }

    /// Tells the sidebar's scroll to hold still. `chrome.activePlainSliderID` is
    /// what `.scrollDisabled` reads there; in the phone's Curve tool there is no
    /// scroll and setting it is harmless.
    private func claimScroll() {
        chrome.activePlainSliderID = "curve.\(channel.rawValue)"
    }

    private func releaseScroll() {
        if chrome.activePlainSliderID?.hasPrefix("curve.") == true {
            chrome.activePlainSliderID = nil
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

    /// Constrain a dragged point: endpoints keep their x on the edge, interior
    /// points stay strictly between their neighbours, everything clamps to 0…1 in y.
    private func clamped(index: Int, to point: CurvePoint, in current: [CurvePoint]) -> CurvePoint {
        let y = min(1, max(0, point.y))
        if index == 0 { return CurvePoint(x: 0, y: y) }
        if index == current.count - 1 { return CurvePoint(x: 1, y: y) }
        let lower = current[index - 1].x + 0.001
        let upper = current[index + 1].x - 0.001
        return CurvePoint(x: min(upper, max(lower, point.x)), y: y)
    }
}

/// The Curve group's panel.
///
/// On the phone it is the zone of the Curve tool (FS-03.13b §2): the graph,
/// 220×220, on the left; on the right a column of the four channel chips,
/// Reset and the how-to line. Region mode trades the graph for its seven
/// sliders; it and the preset shapes are reached from ⋯, where the zone has no
/// room for them. The sidebar keeps its stacked layout, with the same graph
/// drawn under it by the screen.
struct EditorCurvePanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    private var channel: ToneCurveChannel { chrome.curveChannel }
    private var isLinear: Bool {
        controller.editedCurve[channel] == ToneCurveAdjustments.linear
    }

    var body: some View {
        if usesPanelStyle && !isStacked {
            phoneRows
        } else {
            stackedBody
        }
    }

    private var phoneRows: some View {
        Group {
            if chrome.curveMode == .region {
                VStack(spacing: 0) {
                    modeRow
                        .padding(.horizontal, EditorStripLayout.horizontalInset)
                        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
                    ScrollView(.vertical, showsIndicators: false) {
                        regionRows
                    }
                }
            } else {
                pointZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Graph left, channels · Reset · hint right.
    private var pointZone: some View {
        HStack(alignment: .top, spacing: EditorCurvePanel.columnGap) {
            EditorCurveGraph(controller: controller, chrome: chrome)
                .frame(maxWidth: EditorCurvePanel.graphSide, maxHeight: EditorCurvePanel.graphSide)
            VStack(alignment: .leading, spacing: EditorCurvePanel.chipGap) {
                ForEach(ToneCurveChannel.allCases) { option in
                    Button {
                        chrome.curveChannel = option
                    } label: {
                        // The name centred like Reset below it; the dot
                        // pinned to the leading edge, so the four sit in one
                        // column instead of moving with each word's width.
                        Text(option.displayName)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .leading) {
                                Circle()
                                    .fill(option.stripDot)
                                    .frame(width: EditorCurvePanel.dotSide, height: EditorCurvePanel.dotSide)
                            }
                    }
                    .buttonStyle(EditorChipButtonStyle(
                        isSelected: channel == option,
                        horizontalPadding: AppTheme.Spacing.md
                    ))
                    .frame(height: EditorCurvePanel.chipHeight)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(channel == option ? .isSelected : [])
                }
                Button {
                    controller.resetCurve(channel)
                } label: {
                    Text("Reset").frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
                .frame(height: EditorCurvePanel.chipHeight)
                .disabled(isLinear)
                .opacity(isLinear ? EditorTheme.rowDisabled : 1)
                Text("Tap the line to add a point. Drag to move it, double-tap to remove it.")
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.panelHint)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: EditorCurvePanel.columnWidth)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FS-03.13b §2: a 220pt square and a 120pt column of 30pt chips.
    static let graphSide: CGFloat = 220
    static let columnWidth: CGFloat = 120
    static let chipHeight: CGFloat = 30
    static let chipGap: CGFloat = 6
    static let columnGap: CGFloat = 12
    /// Larger than the strips' 8pt dot: here it stands alone at the edge
    /// rather than beside the word.
    static let dotSide: CGFloat = 10

    /// Point · Region. Region shapes the RGB master only, as in Lightroom.
    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(EditorCurveMode.allCases) { mode in
                Button(mode.displayName) {
                    chrome.curveMode = mode
                    if mode == .region { chrome.curveChannel = .rgb }
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: chrome.curveMode == mode))
                .accessibilityAddTraits(chrome.curveMode == mode ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if chrome.curveMode == .region {
                Button("Reset") { controller.resetCurveRegion() }
                    .buttonStyle(EditorChipButtonStyle(isSelected: false))
                    .disabled(controller.editedCurve.region == .identity)
                    .opacity(controller.editedCurve.region == .identity ? EditorTheme.rowDisabled : 1)
            } else {
                // The sidebar's channel row has no room for it: four chips and
                // Reset in ~210pt cut "RGB" to "R…".
                Button("Reset") { controller.resetCurve(channel) }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isLinear ? EditorTheme.dimText : EditorTheme.accent)
                    .disabled(isLinear)
            }
        }
    }

    /// Four regions and the three splits between them.
    private var regionRows: some View {
        VStack(spacing: 0) {
            regionSlider("Highlights", value: controller.editedCurve.region.highlights) { $0.highlights = $1 }
            regionSlider("Lights", value: controller.editedCurve.region.lights) { $0.lights = $1 }
            regionSlider("Darks", value: controller.editedCurve.region.darks) { $0.darks = $1 }
            regionSlider("Shadows", value: controller.editedCurve.region.shadows) { $0.shadows = $1 }
            splitSlider("Shadow Split", value: controller.editedCurve.region.shadowSplit, reset: 0.25) { $0.shadowSplit = $1 }
            splitSlider("Midtone Split", value: controller.editedCurve.region.midtoneSplit, reset: 0.5) { $0.midtoneSplit = $1 }
            splitSlider("Highlight Split", value: controller.editedCurve.region.highlightSplit, reset: 0.75) { $0.highlightSplit = $1 }
        }
    }

    private func regionSlider(
        _ title: String,
        value: Double,
        _ set: @escaping (inout ParametricCurve, Double) -> Void
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: value,
            range: -1...1,
            isBipolar: true,
            valueText: "\(Int((value * 100).rounded()))",
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { new in controller.updateCurveRegion { set(&$0, new) } },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.updateCurveRegion { set(&$0, 0) } }
        )
    }

    private func splitSlider(
        _ title: String,
        value: Double,
        reset: Double,
        _ set: @escaping (inout ParametricCurve, Double) -> Void
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: value,
            range: 0.05...0.95,
            isBipolar: false,
            valueText: "\(Int((value * 100).rounded()))",
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { new in controller.updateCurveRegion { set(&$0, new) } },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.updateCurveRegion { set(&$0, reset) } }
        )
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeRow
            if chrome.curveMode == .region {
                regionRows
                    .padding(.horizontal, -14)
            } else {
                stackedPointBody
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stackedPointBody: some View {
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
                               controller.editedCurve[option] != ToneCurveAdjustments.linear {
                                Circle()
                                    .fill(EditorTheme.accent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: channel == option))
                }
                Spacer(minLength: 0)
            }

            Text("Tap the line to add a point. Drag to move it, double-tap to remove it.")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
                .fixedSize(horizontal: false, vertical: true)

            presetRow
        }
    }

    /// Starting shapes for the shown channel. The chip whose points the channel
    /// currently matches is lit; dragging any point unlights it.
    private var presetRow: some View {
        let inset: CGFloat = usesPanelStyle && !isStacked ? EditorStripLayout.horizontalInset : 14
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ToneCurveAdjustments.presets) { preset in
                    Button(preset.name) {
                        controller.applyCurvePreset(preset, to: channel)
                    }
                    .buttonStyle(EditorChipButtonStyle(
                        isSelected: controller.editedCurve[channel] == preset.points
                    ))
                }
            }
            .frame(maxHeight: .infinity)
        }
        // Bleed the scroll to the panel edges so the row does not clip mid-chip.
        .padding(.horizontal, usesPanelStyle && !isStacked ? 0 : -14)
        .contentMargins(.horizontal, inset, for: .scrollContent)
    }
}

extension ToneCurveChannel {
    /// The channel's own colour: light grey for the RGB master, then red, green, blue.
    var stripDot: Color {
        switch self {
        case .rgb: Color(white: 0.91)
        case .red: EditorTheme.histogramRed
        case .green: EditorTheme.histogramGreen
        case .blue: EditorTheme.histogramBlue
        }
    }
}
