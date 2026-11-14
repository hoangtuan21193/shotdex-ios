import ShotDexKit
import SwiftUI

/// The inspector of 320 (board `MAC_Edit`, FS-18.03 §1): the histogram card,
/// Look and Amount, then the groups in pipeline order. Light opens by
/// default; groups that need their own controls (curves, wheels, mixers)
/// come with the tool rows that build them.
struct MacEditorInspector: View {
    @Bindable var model: MacEditorModel
    /// Open groups, remembered while the editor is up.
    @State private var open: Set<Section> = [.light]

    enum Section: String, CaseIterable, Identifiable {
        case light, toneCurve, color, colorMixer, pointColor, grading, effects, lensBlur, detail, optics, calibration
        var id: String { rawValue }

        var title: String {
            switch self {
            case .light: String(localized: "Light", comment: "Mac editor group")
            case .toneCurve: String(localized: "Tone Curve", comment: "Mac editor group")
            case .color: String(localized: "Color", comment: "Mac editor group")
            case .colorMixer: String(localized: "Color Mixer", comment: "Mac editor group")
            case .pointColor: String(localized: "Point Color", comment: "Mac editor group")
            case .grading: String(localized: "Grading", comment: "Mac editor group")
            case .effects: String(localized: "Effects", comment: "Mac editor group")
            case .lensBlur: String(localized: "Lens Blur", comment: "Mac editor group")
            case .detail: String(localized: "Detail", comment: "Mac editor group")
            case .optics: String(localized: "Optics", comment: "Mac editor group")
            case .calibration: String(localized: "Calibration", comment: "Mac editor group")
            }
        }

        /// The sliders this group draws here, from the shared catalog; nil
        /// for a group whose controls are not sliders.
        func kinds(isRAW: Bool) -> [PhotoAdjustmentKind]? {
            let groups = EditorAdjustmentCatalog.groups(isRAWSource: isRAW, scope: .global)
            func group(_ id: EditorAdjustmentGroup.Identity) -> [PhotoAdjustmentKind] { groups.first { $0.id == id }?.kinds ?? [] }
            switch self {
            case .light: return group(.light)
            case .color: return group(.color)
            case .effects: return group(.effects)
            case .detail: return group(.detail)
            case .optics: return group(.lensProfile) + group(.lensManual) + group(.optics)
            default: return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MacEditorHistogramCard(model: model)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if model.tool == .crop {
                    MacEditorCropSections(model: model)
                        .padding(.top, 8)
                } else {
                    look
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Divider()
                    ForEach(Section.allCases) { section in
                        group(section)
                        Divider()
                    }
                }
            }
        }
        .background(MacTheme.Editor.inspector)
        .disabled(model.load != .ready)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Adjustments", comment: "Mac editor: the inspector"))
    }

    // MARK: Look

    private var look: some View {
        HStack(spacing: 8) {
            Text("Look", comment: "Mac editor: the film look row").foregroundStyle(.secondary)
            Picker(String(localized: "Look", comment: "Mac editor: the film look row"),
                   selection: Binding(get: { model.recipe.filter }, set: { filter in
                       model.apply { $0.filter = filter; $0.lutID = nil }
                   })) {
                ForEach(PhotoFilter.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("editor.look")
            Text("Amount", comment: "Mac editor: how much of the look").font(.system(size: 11)).foregroundStyle(.secondary)
            MacEditorNumberField(text: "\(Int((model.recipe.filterIntensity * 100).rounded()))") { text in
                guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return }
                model.apply { $0.filterIntensity = min(1, max(0, value / 100)) }
            }
            .frame(width: 40)
            .disabled(model.recipe.filter == .original && model.recipe.lutID == nil)
            .accessibilityLabel(String(localized: "Amount", comment: "Mac editor: how much of the look"))
            .accessibilityIdentifier("editor.amount")
        }
        .font(.system(size: 13))
    }

    // MARK: Groups

    @ViewBuilder
    private func group(_ section: Section) -> some View {
        let isOpen = open.contains(section)
        let kinds = section.kinds(isRAW: model.isRAW)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if isOpen { open.remove(section) } else { open.insert(section) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                        Text(section.title).font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityValue(isOpen ? String(localized: "Expanded", comment: "Mac editor group, VoiceOver")
                                           : String(localized: "Collapsed", comment: "Mac editor group, VoiceOver"))
                .accessibilityIdentifier("editor.group.\(section.rawValue)")
                if isOpen, let kinds, kinds.contains(where: { model.recipe.adjustments[$0] != PhotoAdjustments.zero[$0] }) {
                    Button {
                        model.apply { recipe in for kind in kinds { recipe.adjustments[kind] = PhotoAdjustments.zero[kind] } }
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Reset \(section.title)", comment: "Mac editor: reset one group"))
                    .accessibilityLabel(String(localized: "Reset \(section.title)", comment: "Mac editor: reset one group"))
                    .accessibilityIdentifier("editor.reset.\(section.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
            if isOpen {
                if let kinds {
                    VStack(spacing: 0) {
                        ForEach(kinds, id: \.self) { kind in
                            MacEditorSliderRow(model: model, kind: kind)
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Text("This group comes in a later version.", comment: "Mac editor: a group whose controls are not built yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

// MARK: - Slider row

/// A row of 24 (FS-18.03 §1): label · track · value. Drag to change;
/// double-click to reset (its tooltip says so); right-click for Reset and
/// Enter Value…; the value field takes typing.
struct MacEditorSliderRow: View {
    let model: MacEditorModel
    let kind: PhotoAdjustmentKind
    @FocusState private var editsValue: Bool

    private var value: Double { model.recipe.adjustments[kind] }
    private var defaultValue: Double { PhotoAdjustments.zero[kind] }
    private var title: String { EditorAdjustmentCatalog.shortTitle(of: kind) }
    private var isEnabled: Bool { EditorAdjustmentCatalog.isEnabled(kind, in: model.recipe.adjustments) }

    var body: some View {
        if EditorAdjustmentCatalog.format(of: kind) == .toggle {
            Toggle(title, isOn: Binding(get: { value >= 0.5 }, set: { on in model.apply { $0.adjustments[kind] = on ? 1 : 0 } }))
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)
                MacEditorSlider(value: value, range: EditorAdjustmentCatalog.sliderRange(of: kind),
                                isBipolar: EditorAdjustmentCatalog.isBipolar(kind),
                                begin: model.beginChange, change: { model.set(kind, to: $0) }, end: model.endChange,
                                reset: reset)
                    .help(String(localized: "Drag to adjust · double-click to reset", comment: "Mac editor slider tooltip"))
                    .accessibilityLabel(title)
                    .accessibilityValue(EditorAdjustmentCatalog.displayText(value, of: kind))
                MacEditorNumberField(text: EditorAdjustmentCatalog.displayText(value, of: kind)) { text in
                    guard let entered = EditorAdjustmentCatalog.value(fromDisplayText: text, of: kind) else { return }
                    let range = EditorAdjustmentCatalog.sliderRange(of: kind)
                    model.apply { $0.adjustments[kind] = min(range.upperBound, max(range.lowerBound, entered)) }
                }
                .focused($editsValue)
                .frame(width: 50)
                .accessibilityLabel(String(localized: "\(title) value", comment: "Mac editor: a slider's number field"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 24)
            .opacity(isEnabled ? 1 : 0.4)
            .contextMenu {
                Button(String(localized: "Reset", comment: "Mac editor slider menu")) { reset() }
                Button(String(localized: "Enter Value…", comment: "Mac editor slider menu")) { editsValue = true }
            }
            .accessibilityIdentifier("editor.slider.\(kind.rawValue)")
        }
    }

    private func reset() {
        model.apply { $0.adjustments[kind] = defaultValue }
    }
}

/// The value at a row's end: right-aligned, takes typing, Return applies.
struct MacEditorNumberField: View {
    let text: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(MacTheme.Editor.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(MacTheme.Editor.fieldStroke))
            .focused($isFocused)
            .onSubmit { commit(draft); isFocused = false }
            .onAppear { draft = text }
            .onChange(of: text) { _, new in if !isFocused { draft = new } }
            // Leaving the field keeps what was typed; text that is not a number goes back.
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                if draft != text { commit(draft) }
                draft = text
            }
    }
}

// MARK: - Histogram

/// The histogram card (board): three channels, the clipping switches in its
/// corners, and ISO · focal length · aperture · shutter under it.
private struct MacEditorHistogramCard: View {
    @Bindable var model: MacEditorModel

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                if let histogram = model.histogram {
                    Canvas { context, size in
                        // Board: the three channels screened, so their overlap reads light.
                        context.blendMode = .screen
                        draw(histogram.red, color: MacTheme.Editor.histogramRed, in: &context, size: size)
                        draw(histogram.green, color: MacTheme.Editor.histogramGreen, in: &context, size: size)
                        draw(histogram.blue, color: MacTheme.Editor.histogramBlue, in: &context, size: size)
                    }
                    .accessibilityHidden(true)
                } else {
                    Color.clear
                }
                HStack {
                    clipButton(isOn: $model.showsShadowClipping, corner: .bottomLeading,
                               label: String(localized: "Show Shadow Clipping", comment: "Mac editor histogram"), id: "editor.clip.shadows")
                    Spacer()
                    clipButton(isOn: $model.showsHighlightClipping, corner: .topTrailing,
                               label: String(localized: "Show Highlight Clipping", comment: "Mac editor histogram"), id: "editor.clip.highlights")
                }
                .padding(5)
            }
            .frame(height: 64)
            HStack {
                Text(MacEditorExposure.iso(model.details)).frame(maxWidth: .infinity)
                Text(MacEditorExposure.focal(model.details)).frame(maxWidth: .infinity)
                Text(MacEditorExposure.aperture(model.details)).frame(maxWidth: .infinity)
                Text(model.details.shutter.map { $0.hasSuffix("s") ? $0 : $0 + " s" } ?? "—").frame(maxWidth: .infinity)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.bottom, 6)
        }
        .background(MacTheme.Editor.control, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Histogram", comment: "Mac editor: the histogram card"))
    }

    /// Board: an outlined corner triangle, 20 square, pressed ground when on.
    private func clipButton(isOn: Binding<Bool>, corner: UnitPoint, label: String, id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            MacClipTriangle(corner: corner)
                .stroke(isOn.wrappedValue ? MacTheme.Editor.label : MacTheme.Editor.secondaryText, lineWidth: 1.4)
                .frame(width: 9, height: 9)
                .frame(width: 20, height: 20)
                .background(isOn.wrappedValue ? MacTheme.Editor.pressed : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? String(localized: "On", comment: "VoiceOver: a switch is on") : String(localized: "Off", comment: "VoiceOver: a switch is off"))
        .accessibilityIdentifier(id)
    }

    private func draw(_ bins: [Double], color: Color, in context: inout GraphicsContext, size: CGSize) {
        guard bins.count > 1 else { return }
        var path = Path()
        let step = size.width / CGFloat(bins.count - 1)
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in bins.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: size.height * (1 - min(1, CGFloat(value)))))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.55)))
    }
}

enum MacEditorExposure {
    static func iso(_ details: MacEditorModel.Details) -> String { details.iso.map { "ISO \($0)" } ?? "—" }
    static func focal(_ details: MacEditorModel.Details) -> String {
        details.focalLength.map { "\(Int($0.rounded())) mm" } ?? "—"
    }
    static func aperture(_ details: MacEditorModel.Details) -> String {
        details.aperture.flatMap { MetadataFormatter.aperture($0) } ?? "—"
    }
}

/// The clipping switches' glyph: a right triangle in a corner of the card.
private struct MacClipTriangle: Shape {
    let corner: UnitPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if corner == .topTrailing {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// The board's slider: a 3pt rail, the fill from the zero point outward
/// (from the left for a one-way control), a tick at zero, a 12pt knob.
/// Drag to change; double-click resets; arrow keys step by 1%.
struct MacEditorSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let isBipolar: Bool
    let begin: () -> Void
    let change: (Double) -> Void
    let end: () -> Void
    let reset: () -> Void
    /// The value when the drag began: the pointer moves it by its travel.
    @State private var dragOrigin: Double?

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((min(range.upperBound, max(range.lowerBound, v)) - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let origin = isBipolar ? fraction(0) : 0
            let at = fraction(value)
            ZStack(alignment: .leading) {
                Capsule().fill(MacTheme.Editor.sliderTrack).frame(height: 3)
                Capsule().fill(Color.white.opacity(0.85))
                    .frame(width: abs(at - origin) * width, height: 3)
                    .offset(x: min(at, origin) * width)
                if isBipolar {
                    Rectangle().fill(MacTheme.Editor.secondaryText).frame(width: 1, height: 8).offset(x: origin * width - 0.5)
                }
                Circle().fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                    .offset(x: at * width - 6)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            // Double-click resets; a click alone moves nothing; a drag moves the
            // value by how far the pointer goes, wherever it was grabbed.
            .onTapGesture(count: 2) { reset() }
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                if dragOrigin == nil { dragOrigin = value; begin() }
                let delta = Double(drag.translation.width / max(1, width)) * (range.upperBound - range.lowerBound)
                change(min(range.upperBound, max(range.lowerBound, (dragOrigin ?? value) + delta)))
            }.onEnded { _ in
                dragOrigin = nil
                end()
            })
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 100
            begin()
            change(value + (direction == .increment ? step : -step))
            end()
        }
    }
}
