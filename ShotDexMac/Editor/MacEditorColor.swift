import ShotDexKit
import SwiftUI

/// Tone Curve, Color Mixer, Point Color and Grading (board `MAC_EditColor`,
/// FS-18.03 §1c): the same recipe and the same scales as the iPhone's Color
/// panel, laid out as inspector groups.
struct MacEditorColorSection: View {
    let section: MacEditorInspector.Section
    @Bindable var model: MacEditorModel

    init?(_ section: MacEditorInspector.Section, model: MacEditorModel) {
        guard [.toneCurve, .colorMixer, .pointColor, .grading].contains(section) else { return nil }
        self.section = section
        self.model = model
    }

    /// The group's ↺, while it has something to put back.
    @MainActor
    static func reset(_ section: MacEditorInspector.Section, model: MacEditorModel) -> (() -> Void)? {
        let color = model.recipe.color
        switch section {
        case .toneCurve:
            return model.recipe.curve.isIdentity ? nil : { model.apply { $0.curve = .identity } }
        case .colorMixer:
            return color.mixer.isIdentity ? nil : { model.apply { $0.color.mixer = .identity } }
        case .pointColor:
            return color.points.isEmpty ? nil : {
                model.apply { $0.color.points = [] }
                model.selectedPointColorId = nil
            }
        case .grading:
            return color.grading.isIdentity ? nil : { model.apply { $0.color.grading = .identity } }
        default:
            return nil
        }
    }

    var body: some View {
        Group {
            switch section {
            case .toneCurve: MacToneCurveSection(model: model)
            case .colorMixer: MacColorMixerSection(model: model)
            case .pointColor: MacPointColorSection(model: model)
            default: MacGradingSection(model: model)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Tone Curve

private struct MacToneCurveSection: View {
    @Bindable var model: MacEditorModel
    @State private var usesRegions = false
    @State private var channel = ToneCurveChannel.rgb

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MacEditorSegments(options: [false, true], selection: $usesRegions, id: "editor.curve.mode") {
                    $0 ? String(localized: "Region", comment: "Mac editor tone curve: the four-region sliders")
                       : String(localized: "Point", comment: "Mac editor tone curve: points on the curve")
                }
                .frame(width: 120)
                Spacer()
                if !usesRegions {
                    channelPicker
                }
            }
            .padding(.horizontal, 16)
            MacToneCurveEditor(model: model, channel: usesRegions ? .rgb : channel, isEditable: !usesRegions)
                .frame(height: 132)
                .padding(.horizontal, 16)
            if !usesRegions {
                Text("Click the curve to add a point · double-click a point to remove it", comment: "Mac editor tone curve: how to edit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if usesRegions {
                VStack(spacing: 0) {
                    regionRow(String(localized: "Highlights", comment: "Mac editor region curve"), \.highlights)
                    regionRow(String(localized: "Lights", comment: "Mac editor region curve"), \.lights)
                    regionRow(String(localized: "Darks", comment: "Mac editor region curve"), \.darks)
                    regionRow(String(localized: "Shadows", comment: "Mac editor region curve"), \.shadows)
                }
            }
        }
    }

    /// RGB, then a red, a green and a blue dot (board).
    private var channelPicker: some View {
        HStack(spacing: 2) {
            ForEach(ToneCurveChannel.allCases) { option in
                let isOn = channel == option
                Button { channel = option } label: {
                    Group {
                        if option == .rgb {
                            Text("RGB", comment: "Mac editor tone curve: the master channel").font(.system(size: 11, weight: .semibold))
                        } else {
                            Circle().fill(Self.color(of: option)).frame(width: 9, height: 9)
                        }
                    }
                    .frame(minWidth: 24, minHeight: 20)
                    .background(isOn ? MacTheme.Editor.segmentOn : Color.clear, in: RoundedRectangle(cornerRadius: MacTheme.Editor.segmentRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.displayName)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("editor.curve.channel.\(option.rawValue)")
            }
        }
        .padding(1)
        .background(MacTheme.Editor.segmentTrack, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius).strokeBorder(MacTheme.Editor.hairline))
    }

    static func color(of channel: ToneCurveChannel) -> Color {
        switch channel {
        case .rgb: .white
        case .red: MacTheme.Editor.channelRed
        case .green: MacTheme.Editor.channelGreen
        case .blue: MacTheme.Editor.channelBlue
        }
    }

    private func regionRow(_ title: String, _ key: WritableKeyPath<ParametricCurve, Double>) -> some View {
        MacEditorValueRow(
            title: title, value: model.recipe.curve.region[keyPath: key] * 100, range: -100...100, isBipolar: true,
            id: "editor.curve.region.\(title.lowercased())", model: model,
            set: { value, recipe in recipe.curve.region[keyPath: key] = value / 100 })
    }
}

/// The curve over the photo's luminance histogram: drag a point; click the
/// curve to add one where it already passes; double-click a point inside the
/// ends to take it away. "In 128 · Out 152" by the point in hand.
private struct MacToneCurveEditor: View {
    @Bindable var model: MacEditorModel
    let channel: ToneCurveChannel
    let isEditable: Bool
    /// The point held, by index, with the number of points then: a curve
    /// that changed under the drag (⌘Z while holding) drops it.
    @State private var held: Int?
    @State private var heldCount = 0
    /// The point the readout names: the one held, or just let go of.
    @State private var shown: Int?

    private var points: [CurvePoint] { model.recipe.curve[channel] }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: MacTheme.Editor.cardRadius).fill(MacTheme.Editor.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.cardRadius).strokeBorder(MacTheme.Editor.hairline))
                Canvas { context, size in draw(in: &context, size: size) }
                    .accessibilityHidden(true)
                if let index = shown ?? held, points.indices.contains(index) {
                    let point = points[index]
                    Text(String(localized: "In \(Int((point.x * 255).rounded())) · Out \(Int((point.y * 255).rounded()))",
                                comment: "Mac editor tone curve: the point in hand, 0–255"))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MacTheme.Editor.readoutShade, in: RoundedRectangle(cornerRadius: MacTheme.Editor.segmentRadius))
                        .fixedSize()
                        .offset(x: min(size.width - 96, point.x * size.width + 10), y: max(2, (1 - point.y) * size.height - 10))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("editor.curve.readout")
                }
            }
            .contentShape(Rectangle())
            .gesture(isEditable ? drag(size) : nil)
            .simultaneousGesture(isEditable ? SpatialTapGesture(count: 2).onEnded { removePoint(near: $0.location, size: size) } : nil)
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Tone Curve", comment: "Mac editor group"))
        .accessibilityValue(String(localized: "\(points.count) points", comment: "Mac editor tone curve, VoiceOver"))
        .accessibilityIdentifier("editor.curve.canvas")
        .onChange(of: channel) { held = nil; shown = nil }
        // Undo, another photo: the readout's point may be another one now.
        .onChange(of: points.count) { if held == nil { shown = nil } }
        .onChange(of: model.currentId) { held = nil; shown = nil }
        .contextMenu {
            if isEditable, let index = shown, index > 0, index < points.count - 1 {
                Button(String(localized: "Remove Point", comment: "Mac editor tone curve: right-click on the point in hand")) {
                    var next = points
                    next.remove(at: index)
                    model.apply { $0.curve[channel] = next }
                    shown = nil
                }
            }
            if isEditable, points != ToneCurveAdjustments.linear {
                Button(String(localized: "Reset \(channel.displayName) Curve", comment: "Mac editor tone curve: right-click")) {
                    model.apply { $0.curve[channel] = ToneCurveAdjustments.linear }
                    shown = nil
                }
            }
        }
        // Gone mid-drag (Region, the group folded, another photo): the drag's undo step closes.
        .onDisappear { if held != nil { model.endChange(); held = nil } }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        // Grid in quarters.
        var grid = Path()
        for i in 1...3 {
            let x = size.width * CGFloat(i) / 4, y = size.height * CGFloat(i) / 4
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(MacTheme.Editor.curveGrid), lineWidth: 1)
        // The photo's tones behind.
        if let bins = model.histogram?.luminance, bins.count > 1 {
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            let peak = max(0.0001, bins.max() ?? 1)
            for (i, value) in bins.enumerated() {
                area.addLine(to: CGPoint(x: size.width * CGFloat(i) / CGFloat(bins.count - 1),
                                         y: size.height * (1 - CGFloat(value / peak) * 0.8)))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            context.fill(area, with: .color(MacTheme.Editor.curveHistogram))
        }
        // The untouched line.
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: 0, y: size.height)); diagonal.addLine(to: CGPoint(x: size.width, y: 0))
        context.stroke(diagonal, with: .color(MacTheme.Editor.curveGuide), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // The curve.
        let lut = isEditable
            ? ToneCurveMath.lut(points: points, count: 128)
            : ParametricCurveMath.lut(model.recipe.curve.region, count: 128)
        var curve = Path()
        for (i, value) in lut.enumerated() {
            let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(lut.count - 1), y: size.height * (1 - CGFloat(value)))
            if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
        }
        let tint = MacToneCurveSection.color(of: channel)
        context.stroke(curve, with: .color(tint), lineWidth: 1.6)
        guard isEditable else { return }
        for (i, point) in points.enumerated() {
            let center = CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
            // Board: white dots edged in black; the one in hand larger, in an 8pt ring.
            let isHeld = i == (held ?? shown)
            let radius: CGFloat = isHeld ? 5 : 4
            let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(.black), lineWidth: 1)
            if isHeld {
                let ring = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
                context.stroke(ring, with: .color(.white), lineWidth: 1)
            }
        }
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(1, max(0, value.location.x / max(1, size.width)))
                let y = min(1, max(0, 1 - value.location.y / max(1, size.height)))
                if held == nil {
                    let start = value.startLocation
                    if let near = nearest(to: start, size: size) {
                        held = near
                        heldCount = points.count
                    } else {
                        // A click on the curve: a new point where the curve already is.
                        let sx = min(1, max(0, start.x / max(1, size.width)))
                        let lut = ToneCurveMath.lut(points: points, count: 256)
                        let sy = Double(lut[min(255, Int(sx * 255))])
                        guard abs(sy - (1 - start.y / max(1, size.height))) < 0.12,
                              // Not on top of a point that is already there.
                              !points.contains(where: { abs($0.x - sx) < 0.02 }) else { return }
                        var next = points
                        next.append(CurvePoint(x: sx, y: sy))
                        next.sort { $0.x < $1.x }
                        model.beginChange()
                        model.change { $0.curve[channel] = next }
                        held = next.firstIndex { $0.x == sx }
                        heldCount = next.count
                        shown = held
                        return
                    }
                    model.beginChange()
                }
                guard let index = held else { return }
                var next = points
                guard next.count == heldCount, next.indices.contains(index) else { return }
                // The ends stay at the ends; inner points stay between their neighbours.
                let isEnd = index == 0 || index == next.count - 1
                let lower = index > 0 ? next[index - 1].x + 0.01 : 0
                let upper = index < next.count - 1 ? next[index + 1].x - 0.01 : 1
                let movedX = upper >= lower ? min(upper, max(lower, x)) : next[index].x
                next[index] = CurvePoint(x: isEnd ? next[index].x : movedX, y: y)
                model.change { $0.curve[channel] = next }
                shown = index
            }
            .onEnded { _ in
                if held != nil { model.endChange() }
                held = nil
            }
    }

    private func nearest(to location: CGPoint, size: CGSize) -> Int? {
        points.indices.min { a, b in distance(points[a], location, size) < distance(points[b], location, size) }
            .flatMap { distance(points[$0], location, size) < 10 ? $0 : nil }
    }

    private func distance(_ point: CurvePoint, _ location: CGPoint, _ size: CGSize) -> CGFloat {
        hypot(point.x * size.width - location.x, (1 - point.y) * size.height - location.y)
    }

    private func removePoint(near location: CGPoint, size: CGSize) {
        guard let index = nearest(to: location, size: size), index > 0, index < points.count - 1 else { return }
        var next = points
        next.remove(at: index)
        model.apply { $0.curve[channel] = next }
        shown = nil
    }
}

// MARK: - Color Mixer

private struct MacColorMixerSection: View {
    @Bindable var model: MacEditorModel
    /// Hue · Saturation · Luminance, or nil for All.
    @State private var property: ColorMixerProperty? = .hue

    private var mixer: ColorMixerAdjustments { model.recipe.color.mixer }

    var body: some View {
        if model.recipe.adjustments.blackAndWhite >= 0.5 {
            grayMixer
        } else {
            colorMixer
        }
    }

    /// Black & White on: how bright each colour turns grey (the iPhone's B&W mix).
    private var grayMixer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Black & White Mix", comment: "Mac editor color mixer: the grey mix while Black & White is on")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(ColorMixerBand.allCases) { band in
                    MacEditorValueRow(
                        title: band.displayName, value: model.recipe.color.grayMixer[band] * 100, range: -100...100, isBipolar: true,
                        track: [Color(white: 0.15), MacColorTracks.hue(band.centerDegrees), Color(white: 0.92)],
                        id: "editor.gray.\(band.rawValue)", model: model,
                        set: { value, recipe in recipe.color.grayMixer[band] = value / 100 })
                }
            }
        }
    }

    private var colorMixer: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacEditorSegments(options: [ColorMixerProperty.hue, .saturation, .luminance, nil], selection: $property, id: "editor.mixer.property",
                              marked: { option in
                                  // A dot on a tab that holds a change.
                                  ColorMixerBand.allCases.contains { band in
                                      option.map { mixer[band][$0] != 0 } ?? !mixer[band].isIdentity
                                  }
                              }) {
                $0?.displayName ?? String(localized: "All", comment: "Mac editor color mixer: every property of every band")
            }
            .padding(.horizontal, 16)
            if let property {
                VStack(spacing: 0) {
                    ForEach(ColorMixerBand.allCases) { band in row(band, property, title: band.displayName) }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ColorMixerBand.allCases) { band in
                        HStack(spacing: 4) {
                            Text(band.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if !mixer[band].isIdentity {
                                Button { model.apply { $0.color.mixer[band] = .identity } } label: {
                                    Image(systemName: "arrow.counterclockwise").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(String(localized: "Reset \(band.displayName)", comment: "Mac editor color mixer: one band"))
                                .accessibilityLabel(String(localized: "Reset \(band.displayName)", comment: "Mac editor color mixer: one band"))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        ForEach(ColorMixerProperty.allCases) { property in row(band, property, title: property.displayName) }
                    }
                }
            }
        }
    }

    private func row(_ band: ColorMixerBand, _ property: ColorMixerProperty, title: String) -> some View {
        MacEditorValueRow(
            title: title, value: model.recipe.color.mixer[band][property] * 100, range: -100...100,
            isBipolar: true, track: MacColorTracks.mixer(band, property),
            id: "editor.mixer.\(band.rawValue).\(property.rawValue)", model: model,
            set: { value, recipe in recipe.color.mixer[band][property] = value / 100 })
    }
}

// MARK: - Point Color

private struct MacPointColorSection: View {
    @Bindable var model: MacEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(model.recipe.color.points) { point in
                    let isOn = point.id == model.selectedPointColor?.id
                    Button { model.selectedPointColorId = point.id } label: {
                        // Board: the chosen one sits in a 2pt gap and a 1.5pt white ring.
                        Circle().fill(MacColorTracks.reference(point))
                            .frame(width: 20, height: 20)
                            .padding(2)
                            .overlay(Circle().strokeBorder(isOn ? Color.white : Color.clear, lineWidth: 1.5).padding(-1.5))
                            .padding(1.5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Color \(MacColorTracks.hexReference(point))", comment: "Mac editor point color swatch, VoiceOver"))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("editor.point.swatch")
                }
                Button { model.isPickingColor.toggle() } label: {
                    Label(model.isPickingColor ? String(localized: "Picking…", comment: "Mac editor point color: the eyedropper is out")
                                               : String(localized: "Pick Color", comment: "Mac editor point color: take the eyedropper"),
                          systemImage: "eyedropper")
                        .font(.system(size: 12, weight: model.isPickingColor ? .semibold : .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(model.isPickingColor ? MacTheme.Editor.segmentOn : MacTheme.Editor.control,
                                    in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canAddPointColor || model.tool != .adjust)
                .help(model.tool != .adjust
                      ? String(localized: "Back in Adjust, pick a color from the photo", comment: "Mac editor point color: eyedropper off in Crop")
                      : model.canAddPointColor
                      ? String(localized: "Click a color in the photo to change just that color", comment: "Mac editor point color: eyedropper tooltip")
                      : String(localized: "Up to \(PointColorAdjustment.maximumCount) colors", comment: "Mac editor point color: the limit"))
                .accessibilityIdentifier("editor.point.pick")
                Spacer()
                if model.selectedPointColor != nil {
                    Button { model.removeSelectedPointColor() } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Remove This Color", comment: "Mac editor point color"))
                    .accessibilityLabel(String(localized: "Remove This Color", comment: "Mac editor point color"))
                    .accessibilityIdentifier("editor.point.remove")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
            if model.isPickingColor {
                Text("Click a color in the photo · Esc to cancel", comment: "Mac editor point color: the eyedropper is out")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else if !model.canAddPointColor {
                Text("\(PointColorAdjustment.maximumCount) of \(PointColorAdjustment.maximumCount) colors — remove one to pick another",
                     comment: "Mac editor point color: at the limit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if let point = model.selectedPointColor {
                VStack(spacing: 0) {
                    row(String(localized: "Hue", comment: "Mac editor point color"), point.hueShift * 100, -100...100, true,
                        MacColorTracks.pointHue(point), "hue") { $0.hueShift = $1 / 100 }
                    row(String(localized: "Saturation", comment: "Mac editor point color"), point.saturationShift * 100, -100...100, true,
                        MacColorTracks.pointSaturation(point), "saturation") { $0.saturationShift = $1 / 100 }
                    row(String(localized: "Luminance", comment: "Mac editor point color"), point.luminanceShift * 100, -100...100, true,
                        MacColorTracks.pointLuminance(point), "luminance") { $0.luminanceShift = $1 / 100 }
                    row(String(localized: "Range", comment: "Mac editor point color"), point.range * 100, 0...100, false,
                        nil, "range") { $0.range = $1 / 100 }
                }
            } else if !model.isPickingColor {
                Text("Pick a color in the photo to change only that color.", comment: "Mac editor point color: empty state")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func row(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ isBipolar: Bool, _ track: [Color]?,
                     _ key: String, _ set: @escaping (inout PointColorAdjustment, Double) -> Void) -> some View {
        MacEditorValueRow(
            title: title, value: value, range: range, isBipolar: isBipolar, track: track, resetValue: key == "range" ? 50 : 0,
            id: "editor.point.\(key)", model: model,
            change: { value, inOneStep in model.changeSelectedPointColor(inOneStep: inOneStep) { set(&$0, value) } })
    }
}

// MARK: - Grading

private struct MacGradingSection: View {
    @Bindable var model: MacEditorModel
    @State private var region = ColorGradingRegion.shadows

    var body: some View {
        let wheel = model.recipe.color.grading[region]
        VStack(alignment: .leading, spacing: 6) {
            MacEditorSegments(options: ColorGradingRegion.allCases, selection: $region, id: "editor.grading.region") { $0.displayName }
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                MacEditorValueRow(
                    title: String(localized: "Hue", comment: "Mac editor grading"), value: wheel.hue, range: 0...360, isBipolar: false,
                    track: MacColorTracks.rainbow, format: .degrees, id: "editor.grading.hue", model: model,
                    set: { [region] value, recipe in recipe.color.grading[region].hue = value })
                MacEditorValueRow(
                    title: String(localized: "Saturation", comment: "Mac editor grading"), value: wheel.saturation * 100, range: 0...100,
                    isBipolar: false, track: [Color(white: 0.5), Color(hue: wheel.hue / 360, saturation: 0.8, brightness: 0.88)],
                    id: "editor.grading.saturation", model: model,
                    set: { [region] value, recipe in recipe.color.grading[region].saturation = value / 100 })
                MacEditorValueRow(
                    title: String(localized: "Luminance", comment: "Mac editor grading"), value: wheel.luminance * 100, range: -100...100,
                    isBipolar: true, id: "editor.grading.luminance", model: model,
                    set: { [region] value, recipe in recipe.color.grading[region].luminance = value / 100 })
                MacEditorValueRow(
                    title: String(localized: "Blending", comment: "Mac editor grading"), value: model.recipe.color.grading.blending * 100,
                    range: 0...100, isBipolar: false, resetValue: 50, id: "editor.grading.blending", model: model,
                    set: { value, recipe in recipe.color.grading.blending = value / 100 })
                MacEditorValueRow(
                    title: String(localized: "Balance", comment: "Mac editor grading"), value: model.recipe.color.grading.balance * 100,
                    range: -100...100, isBipolar: true, id: "editor.grading.balance", model: model,
                    set: { value, recipe in recipe.color.grading.balance = value / 100 })
            }
        }
    }
}

// MARK: - Pieces

/// A row of 24 for a value that is not a `PhotoAdjustmentKind`: label ·
/// slider · boxed number, the same drag, double-click and typing as the
/// Light rows.
struct MacEditorValueRow: View {
    enum Format { case signed, plain, degrees, pixels }

    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let isBipolar: Bool
    var track: [Color]? = nil
    var format = Format.signed
    let id: String
    let model: MacEditorModel
    /// `value` (display units) into the recipe; `inOneStep` for a typed value or a reset.
    let change: (Double, Bool) -> Void

    init(title: String, value: Double, range: ClosedRange<Double>, isBipolar: Bool, track: [Color]? = nil, format: Format = .signed,
         resetValue: Double = 0, id: String, model: MacEditorModel, set: @escaping (Double, inout PhotoEditRecipe) -> Void) {
        self.init(title: title, value: value, range: range, isBipolar: isBipolar, track: track, format: format,
                  resetValue: resetValue, id: id, model: model,
                  change: { value, inOneStep in
                      if inOneStep { model.apply { set(value, &$0) } } else { model.change { set(value, &$0) } }
                  })
    }

    init(title: String, value: Double, range: ClosedRange<Double>, isBipolar: Bool, track: [Color]? = nil, format: Format = .signed,
         resetValue: Double = 0, id: String, model: MacEditorModel, change: @escaping (Double, Bool) -> Void) {
        self.resetValue = resetValue
        self.title = title
        let format = format == .signed && !isBipolar ? .plain : format
        self.value = value
        self.range = range
        self.isBipolar = isBipolar
        self.track = track
        self.format = format
        self.id = id
        self.model = model
        self.change = change
    }

    /// Where double-click and Reset put it (display units).
    var resetValue = 0.0

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            MacEditorSlider(value: value, range: range, isBipolar: isBipolar,
                            begin: model.beginChange, change: { change($0, false) }, end: model.endChange,
                            reset: { change(resetValue, true) }, track: track)
                .help(String(localized: "Drag to adjust · double-click to reset", comment: "Mac editor slider tooltip"))
                .accessibilityLabel(title)
                .accessibilityValue(Self.text(value, format))
            MacEditorNumberField(text: Self.text(value, format)) { text in
                guard let entered = Self.parse(text) else { return }
                change(min(range.upperBound, max(range.lowerBound, entered)), true)
            }
            .frame(width: 50)
            .accessibilityLabel(String(localized: "\(title) value", comment: "Mac editor: a slider's number field"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 22)
        .contextMenu {
            Button(String(localized: "Reset", comment: "Mac editor slider menu")) { change(resetValue, true) }
        }
        .accessibilityIdentifier(id)
    }

    /// "+8", "−12", "0", "214°".
    static func text(_ value: Double, _ format: Format) -> String {
        let rounded = Int(value.rounded())
        switch format {
        case .degrees: return "\(rounded)°"
        case .signed: return rounded > 0 ? "+\(rounded)" : rounded < 0 ? "\u{2212}\(-rounded)" : "0"
        case .plain: return "\(rounded)"
        case .pixels: return "\(rounded) px"
        }
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)
        return (try? Double(cleaned, format: .number)) ?? Double(cleaned)
    }
}

/// A segmented row drawn like the board's (pressed fill on the one chosen).
struct MacEditorSegments<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let id: String
    var marked: (Option) -> Bool = { _ in false }
    let title: (Option) -> String

    init(options: [Option], selection: Binding<Option>, id: String, marked: @escaping (Option) -> Bool = { _ in false },
         title: @escaping (Option) -> String) {
        self.options = options
        _selection = selection
        self.id = id
        self.marked = marked
        self.title = title
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(title(option) + (marked(option) ? " •" : ""))
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? MacTheme.Editor.label : MacTheme.Editor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: MacTheme.Editor.segmentRadius).fill(MacTheme.Editor.segmentOn)
                                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(title(option))")
            }
        }
        .padding(2)
        .background(MacTheme.Editor.segmentTrack, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius).strokeBorder(MacTheme.Editor.hairline))
    }
}

/// The coloured rails (board): each band's hues, a grey-to-colour ramp,
/// dark-to-light; the grading hue as the whole wheel.
enum MacColorTracks {
    static func hue(_ degrees: Double, saturation: Double = 0.85, brightness: Double = 0.95) -> Color {
        Color(hue: ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360,
              saturation: saturation, brightness: brightness)
    }

    static func mixer(_ band: ColorMixerBand, _ property: ColorMixerProperty) -> [Color] {
        let center = band.centerDegrees
        switch property {
        case .hue: return [hue(center - 25), hue(center), hue(center + 25)]
        case .saturation: return [Color(white: 0.55), hue(center)]
        case .luminance: return [hue(center, brightness: 0.25), hue(center), hue(center, saturation: 0.35, brightness: 1)]
        }
    }

    static let rainbow: [Color] = [0, 50, 130, 195, 245, 330, 360].map { hue(Double($0)) }

    static func reference(_ point: PointColorAdjustment) -> Color {
        Color(hue: point.referenceHue / 360, saturation: point.referenceSaturation, brightness: point.referenceValue)
    }

    static func hexReference(_ point: PointColorAdjustment) -> String {
        let color = NSColor(hue: point.referenceHue / 360, saturation: point.referenceSaturation, brightness: point.referenceValue, alpha: 1)
            .usingColorSpace(.sRGB) ?? .gray
        return MacColorSampler.hex(SIMD3(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)))
    }

    static func pointHue(_ point: PointColorAdjustment) -> [Color] {
        [hue(point.referenceHue - 30, saturation: max(0.3, point.referenceSaturation), brightness: point.referenceValue),
         reference(point),
         hue(point.referenceHue + 30, saturation: max(0.3, point.referenceSaturation), brightness: point.referenceValue)]
    }

    static func pointSaturation(_ point: PointColorAdjustment) -> [Color] {
        [Color(white: point.referenceValue * 0.8), hue(point.referenceHue, saturation: 0.85, brightness: point.referenceValue)]
    }

    static func pointLuminance(_ point: PointColorAdjustment) -> [Color] {
        [hue(point.referenceHue, saturation: point.referenceSaturation, brightness: 0.18),
         hue(point.referenceHue, saturation: point.referenceSaturation * 0.6, brightness: 0.95)]
    }
}

// MARK: - Eyedropper over the photo

/// While Point Color's eyedropper is out: a loupe of the pixels under the
/// pointer (10×10, one cell a pixel, ringed in their colour) with the hex
/// under it. A click adds the colour; Esc puts the eyedropper away.
struct MacEditorColorPicker: View {
    let model: MacEditorModel
    let imageRect: CGRect
    @State private var location: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: imageRect.width, height: imageRect.height)

                .onContinuousHover(coordinateSpace: .named(MacEditorCropOverlay.space)) { phase in
                    if case .active(let point) = phase, imageRect.contains(point) { location = point } else { location = nil }
                }
                // Press to see the loupe, move to aim, let go to pick (a plain click picks too).
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacEditorCropOverlay.space))
                    .onChanged { value in if imageRect.contains(value.location) { location = value.location } }
                    .onEnded { value in
                        // Let go off the photo: the eyedropper goes away.
                        guard imageRect.contains(value.location) else { model.isPickingColor = false; return }
                        model.addPointColor(at: normalized(value.location))
                    })
                .pointerStyle(.rectSelection)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Photo, pick a color", comment: "Mac editor: the eyedropper over the photo, VoiceOver"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("editor.point.canvas")
                // Laid out over the photo (an offset would leave the hover area at the corner).
                .position(x: imageRect.midX, y: imageRect.midY)
                #if DEBUG
                // `-ShotDexPickerAt 0.4,0.3`: the loupe where a screenshot can see it
                // (the UI driver moves the pointer without the moves hover needs).
                .onAppear {
                    let parts = (UserDefaults.standard.string(forKey: "ShotDexPickerAt") ?? "").split(separator: ",").compactMap { Double($0) }
                    if parts.count == 2 {
                        location = CGPoint(x: imageRect.minX + imageRect.width * parts[0], y: imageRect.minY + imageRect.height * parts[1])
                    }
                }
                #endif
            if let location, let image = model.samplingImage,
               let sample = MacColorSampler.pixels(in: image, at: normalized(location), side: 10) {
                // The pixel under the pointer, from the sample already read.
                loupe(sample, center: sample.pixels.indices.contains(sample.pointer.row * sample.width + sample.pointer.column)
                      ? sample.pixels[sample.pointer.row * sample.width + sample.pointer.column] : nil)
                    .position(x: location.x, y: location.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: Double((point.x - imageRect.minX) / max(1, imageRect.width)),
                        y: Double((point.y - imageRect.minY) / max(1, imageRect.height)))
    }

    private func loupe(_ sample: (pixels: [SIMD3<Double>], width: Int, pointer: (column: Int, row: Int)),
                       center: SIMD3<Double>?) -> some View {
        let ring = center.map { Color(red: $0.x, green: $0.y, blue: $0.z) } ?? .white
        return VStack(spacing: 6) {
            Canvas { context, size in
                let columns = max(1, sample.width), rows = max(1, sample.pixels.count / columns)
                let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
                for (i, rgb) in sample.pixels.enumerated() {
                    let rect = CGRect(x: CGFloat(i % columns) * cell.width, y: CGFloat(i / columns) * cell.height,
                                      width: cell.width + 0.5, height: cell.height + 0.5)
                    context.fill(Path(rect), with: .color(Color(red: rgb.x, green: rgb.y, blue: rgb.z)))
                }
                // The pixel under the pointer (off centre at the photo's edge, where fewer pixels came).
                let middle = CGRect(x: CGFloat(sample.pointer.column) * cell.width, y: CGFloat(sample.pointer.row) * cell.height,
                                    width: cell.width, height: cell.height)
                context.stroke(Path(middle), with: .color(.white), lineWidth: 1.5)
                context.stroke(Path(middle.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.6)), lineWidth: 1)
            }
            // Board: 84pt of pixels in a 4pt ring of the colour under the pointer, 92 in all.
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .padding(4)
            .background(Circle().fill(ring))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 9, y: 6)
            Text(center.map(MacColorSampler.hex) ?? "")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(MacTheme.Editor.readoutShade, in: Capsule())
        }
        .offset(y: 16)
    }
}
