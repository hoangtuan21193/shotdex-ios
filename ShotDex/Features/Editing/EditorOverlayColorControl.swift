import SwiftUI
import UIKit
import ShotDexKit

/// Colour control for an overlay layer: a swatch row for the colours a watermark
/// actually uses, and the grading wheel behind a Custom toggle for everything else.
///
/// No `ColorPicker`. The app builds its colour UI by hand everywhere else — the
/// accent row in Settings says so in as many words — and the system picker's sheet
/// would cover the photo the colour is being judged against.
struct EditorOverlayColorControl: View {
    @Bindable var chrome: EditorChromeModel
    /// Distinguishes this control's sliders from the other colour control in the
    /// same panel, so dragging the outline's brightness does not highlight the
    /// fill's row.
    let idPrefix: String
    let color: OverlayColor
    let onBegin: () -> Void
    let onChange: (OverlayColor) -> Void
    let onEnd: () -> Void

    @State private var showsWheel = false
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    /// The greys a burnt-in credit line is nearly always one of, plus two tints
    /// for a coloured logo lockup.
    private static let swatches: [OverlayColor] = [
        .white,
        OverlayColor(white: 0.72),
        OverlayColor(white: 0.4),
        .black,
        OverlayColor(red: 0.96, green: 0.86, blue: 0.66),
        OverlayColor(red: 0.92, green: 0.27, blue: 0.24),
    ]

    var body: some View {
        if usesPanelStyle && !isStacked {
            phoneRow
        } else {
            VStack(spacing: 0) {
                swatchRow
                if showsWheel {
                    wheelRows
                }
            }
        }
    }

    /// Phone (FS-05.02 §6): one 40pt row — label, the six swatches, a hairline,
    /// and the custom swatch (a hue ring whose core is the colour now) that opens
    /// the palette over the whole parameter zone.
    private var phoneRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("Color")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.panelText)
                .frame(width: EditorLayoutMetrics.editorPanelRowLabelWidth, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { pair in
                    phoneSwatch(pair.element)
                        .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(EditorTheme.trackBorder).frame(width: 1, height: 18)
            Button {
                chrome.colorPalette = EditorColorPaletteRequest(
                    id: idPrefix,
                    color: { color },
                    onBegin: onBegin,
                    onChange: onChange,
                    onEnd: onEnd
                )
            } label: {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    ))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .fill(isCustom ? swiftUIColor(color) : EditorTheme.panelSolid)
                            .padding(4)
                    }
                    .padding(3)
                    .overlay {
                        if isCustom { Circle().strokeBorder(.white, lineWidth: 1.5) }
                    }
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom color")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }

    /// A colour that is none of the six swatches.
    private var isCustom: Bool { !Self.swatches.contains { isClose($0, color) } }

    private func phoneSwatch(_ candidate: OverlayColor) -> some View {
        let isSelected = isClose(candidate, color)
        return Button {
            onBegin()
            onChange(candidate)
            onEnd()
        } label: {
            Circle()
                .fill(swiftUIColor(candidate))
                .frame(width: 20, height: 20)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                .padding(2)
                .overlay {
                    if isSelected { Circle().strokeBorder(.white, lineWidth: 1.5) }
                }
                .frame(width: 30, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilityName(candidate))
    }

    private var swatchRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { pair in
                swatch(pair.element)
            }
            Spacer(minLength: 0)
            Button(showsWheel ? "Done" : "Custom") {
                withAnimation(EditorTheme.animation) { showsWheel.toggle() }
            }
            .buttonStyle(EditorTextButtonStyle())
        }
        .padding(.leading, 14)
        .frame(height: 44)
    }

    private func swatch(_ candidate: OverlayColor) -> some View {
        let isSelected = isClose(candidate, color)
        return Button {
            onBegin()
            onChange(candidate)
            onEnd()
        } label: {
            Circle()
                .fill(swiftUIColor(candidate))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle().strokeBorder(EditorTheme.hairline, lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(EditorTheme.accent, lineWidth: 2)
                            .frame(width: 33, height: 33)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(accessibilityName(candidate))
    }

    @ViewBuilder
    private var wheelRows: some View {
        let hsv = ColorRenderMath.hsv(
            fromRed: color.red,
            green: color.green,
            blue: color.blue
        )
        EditorColorWheel(
            hue: hsv.hue / 360,
            saturation: hsv.saturation,
            diameter: 132,
            onBegin: onBegin,
            onChange: { hue, saturation in
                // Brightness is the slider's business; a wheel touch must not
                // change how bright the colour is, only which colour it is.
                onChange(make(hue: hue * 360, saturation: saturation, value: hsv.value))
            },
            onEnd: onEnd,
            onReset: {
                onBegin()
                onChange(make(hue: hsv.hue, saturation: 0, value: hsv.value))
                onEnd()
            }
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        EditorPlainSliderRow(
            title: "Brightness",
            value: hsv.value * 100,
            range: 0...100,
            isBipolar: false,
            valueText: String(format: "%.0f%%", hsv.value * 100),
            isActive: chrome.activePlainSliderID == brightnessID,
            trackGradient: LinearGradient(
                colors: [
                    .black,
                    swiftUIColor(make(hue: hsv.hue, saturation: hsv.saturation, value: 1)),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            onBeginDrag: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chrome.activePlainSliderID = brightnessID
                onBegin()
            },
            onDrag: { value in
                onChange(
                    make(hue: hsv.hue, saturation: hsv.saturation, value: value / 100)
                )
            },
            onEndDrag: {
                chrome.activePlainSliderID = nil
                onEnd()
            },
            onReset: {
                onBegin()
                onChange(make(hue: hsv.hue, saturation: hsv.saturation, value: 1))
                onEnd()
            }
        )
    }

    private var brightnessID: String { "\(idPrefix).brightness" }

    private func make(hue: Double, saturation: Double, value: Double) -> OverlayColor {
        let rgb = ColorRenderMath.rgb(
            from: ColorRenderMath.HSV(hue: hue, saturation: saturation, value: value)
        )
        return OverlayColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func swiftUIColor(_ color: OverlayColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }

    /// Swatch selection is a visual match, not an identity test: a colour dialled
    /// on the wheel to within a rounding error of white should light the white
    /// swatch rather than leaving every swatch dark.
    private func isClose(_ a: OverlayColor, _ b: OverlayColor) -> Bool {
        abs(a.red - b.red) < 0.02
            && abs(a.green - b.green) < 0.02
            && abs(a.blue - b.blue) < 0.02
    }

    private func accessibilityName(_ color: OverlayColor) -> String {
        if isClose(color, .white) { return "White" }
        if isClose(color, .black) { return "Black" }
        if color.red == color.green, color.green == color.blue {
            return "Grey \(Int(color.red * 100)) percent"
        }
        return "Colour swatch"
    }
}

/// The phone's custom colour palette (FS-05.02 §6), in place of the parameter
/// zone — the panel keeps its height. `‹ · Color · hex · eyedropper` (36pt),
/// the session's Recent colours (32pt), then Hue / Saturation / Brightness (36pt
/// each). The eyedropper arms a tap on the photo; the colour under it is taken.
struct EditorColorPalettePanel: View {
    @Bindable var chrome: EditorChromeModel
    let request: EditorColorPaletteRequest
    /// What the palette shows. The request's getter is only the colour at the
    /// moment the palette opened, so every write also lands here.
    @State private var shown: OverlayColor?

    private var color: OverlayColor { shown ?? request.color() }

    private func write(_ next: OverlayColor, bracketed: Bool = false) {
        shown = next
        if bracketed { request.onBegin() }
        request.onChange(next)
        if bracketed { request.onEnd() }
    }
    private var hsv: ColorRenderMath.HSV {
        ColorRenderMath.hsv(fromRed: color.red, green: color.green, blue: color.blue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            recentRow
            channel("Hue", value: hsv.hue / 360, gradient: LinearGradient(
                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                startPoint: .leading, endPoint: .trailing
            ), text: "\(Int(hsv.hue.rounded()))°") { value in
                make(hue: value * 360, saturation: hsv.saturation, value: hsv.value)
            }
            channel("Saturation", value: hsv.saturation, gradient: LinearGradient(
                colors: [swiftUI(make(hue: hsv.hue, saturation: 0, value: hsv.value)),
                         swiftUI(make(hue: hsv.hue, saturation: 1, value: hsv.value))],
                startPoint: .leading, endPoint: .trailing
            ), text: "\(Int((hsv.saturation * 100).rounded()))") { value in
                make(hue: hsv.hue, saturation: value, value: hsv.value)
            }
            channel("Brightness", value: hsv.value, gradient: LinearGradient(
                colors: [.black, swiftUI(make(hue: hsv.hue, saturation: hsv.saturation, value: 1))],
                startPoint: .leading, endPoint: .trailing
            ), text: "\(Int((hsv.value * 100).rounded()))") { value in
                make(hue: hsv.hue, saturation: hsv.saturation, value: value)
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                chrome.rememberRecentColor(color)
                chrome.markupColorSampler = nil
                chrome.colorPalette = nil
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close color palette")
            Text("Color")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            HStack(spacing: AppTheme.Spacing.xs) {
                Circle().fill(swiftUI(color)).frame(width: 10, height: 10)
                Text(hex)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            }
            Button {
                if chrome.markupColorSampler == nil {
                    chrome.markupColorSampler = { picked in write(picked, bracketed: true) }
                } else {
                    chrome.markupColorSampler = nil
                }
            } label: {
                Image(systemName: "eyedropper")
                    .frame(width: 20)
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: chrome.markupColorSampler != nil))
            .accessibilityLabel("Pick a color from the photo")
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(height: 36)
    }

    private var recentRow: some View {
        HStack(spacing: 10) {
            Text("Recent")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.panelText)
                .frame(width: EditorLayoutMetrics.editorPanelRowLabelWidth, alignment: .leading)
            if chrome.recentColors.isEmpty {
                Text("None yet")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelHint)
            }
            ForEach(Array(chrome.recentColors.enumerated()), id: \.offset) { pair in
                Button {
                    write(pair.element, bracketed: true)
                } label: {
                    Circle()
                        .fill(swiftUI(pair.element))
                        .frame(width: 18, height: 18)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                        .frame(width: 26, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent color")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: 32)
    }

    private func channel(
        _ title: String,
        value: Double,
        gradient: LinearGradient,
        text: String,
        make: @escaping (Double) -> OverlayColor
    ) -> some View {
        EditorValueSlider(
            label: title,
            value: value,
            range: 0...1,
            valueText: text,
            trackGradient: gradient,
            onBeginDrag: request.onBegin,
            onDrag: { write(make($0)) },
            onEndDrag: { _, _, _ in request.onEnd() },
            onReset: {}
        )
        .frame(height: 36)
        .clipped()
    }

    private var hex: String {
        let r = Int((color.red * 255).rounded()), g = Int((color.green * 255).rounded()), b = Int((color.blue * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func make(hue: Double, saturation: Double, value: Double) -> OverlayColor {
        let rgb = ColorRenderMath.rgb(from: ColorRenderMath.HSV(hue: hue, saturation: saturation, value: value))
        return OverlayColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func swiftUI(_ color: OverlayColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}
