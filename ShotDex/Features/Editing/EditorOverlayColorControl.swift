import SwiftUI
import UIKit

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
        VStack(spacing: 0) {
            swatchRow
            if showsWheel {
                wheelRows
            }
        }
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
