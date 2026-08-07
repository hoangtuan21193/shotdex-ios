import SwiftUI
import UIKit

// The Color tool used to be one tab behind a Mixer | Point Color | Grading
// section picker; it is now three sibling tabs (`PhotoEditorTool.colorMixer` /
// `.pointColor` / `.colorGrading`), so each block is one tap and owns the whole
// panel. `PhotoEditorScreen.toolPanel` renders one of the three section views
// below directly — there is no wrapper and no picker.

// MARK: - Mixer

struct EditorColorMixerSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    /// A channel target strip (28c §6): "All" shows every channel's HUE / SAT / LUM
    /// in one scroll (the previous shape); picking a channel narrows to just that
    /// channel's three rows, each track tinted the way the channel would shift.
    var body: some View {
        VStack(spacing: 0) {
            channelStrip
                .padding(.top, 8)
                .padding(.bottom, 4)
            if let band = chrome.mixerChannel {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        mixerRow(band: band, property: .hue, title: "Hue")
                        mixerRow(band: band, property: .saturation, title: "Saturation")
                        mixerRow(band: band, property: .luminance, title: "Luminance")
                        Color.clear.frame(height: 16)
                    }
                }
                .scrollDisabled(chrome.activePlainSliderID != nil)
            } else {
                allChannelsScroll
            }
        }
    }

    private var channelStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button("All") {
                    withAnimation(EditorTheme.animation) { chrome.mixerChannel = nil }
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: chrome.mixerChannel == nil))

                ForEach(ColorMixerBand.allCases) { band in
                    let isSelected = chrome.mixerChannel == band
                    Button {
                        withAnimation(EditorTheme.animation) { chrome.mixerChannel = band }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(EditorColorMixerStyle.hueColor(
                                    band.centerDegrees,
                                    saturation: 0.85,
                                    brightness: 0.95
                                ))
                                .frame(width: 12, height: 12)
                                .overlay {
                                    Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                }
                            Text(band.displayName)
                        }
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
                    .accessibilityLabel(band.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private var allChannelsScroll: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(ColorMixerProperty.allCases) { property in
                    Section {
                        ForEach(ColorMixerBand.allCases) { band in
                            mixerRow(band: band, property: property, title: band.displayName)
                        }
                        .padding(.bottom, 2)
                    } header: {
                        EditorGroupHeader(
                            title: property.displayName,
                            isFirst: property == ColorMixerProperty.allCases.first,
                            onReset: { controller.resetColorMixer(property: property) }
                        )
                    }
                }
                Color.clear.frame(height: 16)
            }
        }
        .scrollDisabled(chrome.activePlainSliderID != nil)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [EditorTheme.panel.opacity(0), EditorTheme.panel],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)
        }
    }

    private func mixerRow(
        band: ColorMixerBand,
        property: ColorMixerProperty,
        title: String
    ) -> some View {
        let sliderID = "mixer.\(property.rawValue).\(band.rawValue)"
        return EditorPlainSliderRow(
            title: title,
            value: controller.mixerValue(band: band, property: property) * 100,
            range: -100...100,
            isBipolar: true,
            valueText: EditorColorFormat.signed(
                controller.mixerValue(band: band, property: property) * 100
            ),
            isActive: chrome.activePlainSliderID == sliderID,
            detent: 0,
            trackGradient: EditorColorMixerStyle.gradient(band: band, property: property),
            onBeginDrag: {
                controller.beginContinuousChange()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chrome.activePlainSliderID = sliderID
            },
            onDrag: { value in
                controller.setMixerValue(value / 100, band: band, property: property)
            },
            onEndDrag: {
                controller.endContinuousChange()
                chrome.activePlainSliderID = nil
            },
            onReset: {
                controller.setMixerValue(0, band: band, property: property)
            }
        )
    }
}

// MARK: - Point Color

struct EditorPointColorSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            swatchRow
                .padding(.top, 6)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if let point = controller.selectedPointColor {
                        pointSliders(point)
                    } else {
                        Text("Drag on the photo — the loupe shows the pixel under your finger. Lift to pick it.")
                            .font(EditorTheme.rowLabel)
                            .foregroundStyle(EditorTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 40)
                    }
                    Color.clear.frame(height: 16)
                }
            }
            .scrollDisabled(chrome.activePlainSliderID != nil)
        }
    }

    /// The eyedropper shares this row with the swatches, so it is sized by how
    /// much there is to share it with: on an empty section it is the only thing
    /// to do here and spans the whole width with its label showing, and the first
    /// sample collapses it into the icon to make room for the swatch it just
    /// created. Same button throughout — the label and the width animate, so the
    /// collapse reads as the button stepping aside rather than being replaced.
    private var swatchRow: some View {
        HStack(spacing: 10) {
            eyedropperButton
            if !controller.pointColors.isEmpty {
                swatches
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .animation(EditorTheme.animation, value: controller.pointColors.isEmpty)
    }

    private var isEyedropperCollapsed: Bool {
        !controller.pointColors.isEmpty
    }

    private var eyedropperButton: some View {
        let isEnabled = controller.canAddPointColor || chrome.isEyedropperActive
        return Button {
            withAnimation(EditorTheme.animation) {
                chrome.isEyedropperActive.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 13, weight: .semibold))
                if !isEyedropperCollapsed {
                    Text("Pick a Color from the Photo")
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isEyedropperCollapsed ? 12 : 16)
            .frame(maxWidth: isEyedropperCollapsed ? nil : .infinity)
            .frame(height: 34)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("Sample a color")
        .accessibilityValue(chrome.isEyedropperActive ? "Armed" : "Off")
    }

    /// Accent while armed — and while the section is still empty, where the
    /// button is the section's only call to action.
    private var fill: Color {
        chrome.isEyedropperActive || !isEyedropperCollapsed
            ? EditorTheme.accent
            : EditorTheme.control
    }

    private var swatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.pointColors) { point in
                    let isSelected = controller.selectedPointColorID == point.id
                    Button {
                        controller.selectedPointColorID = point.id
                    } label: {
                        Circle()
                            .fill(EditorColorMixerStyle.referenceColor(of: point))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? EditorTheme.accent : EditorTheme.hairline,
                                    lineWidth: isSelected ? 2 : 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    // A swatch is a 28pt dot, and the only thing you can do to it
                    // besides select it is throw it away — so the long press goes
                    // straight to that instead of selecting the point first and
                    // then reaching for Delete Point at the bottom of the sliders.
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(EditorTheme.animation) {
                                controller.removePointColor(id: point.id)
                            }
                        } label: {
                            Label("Delete Point Color", systemImage: "trash")
                        }
                    }
                    .accessibilityLabel("Point color")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func pointSliders(_ point: PointColorAdjustment) -> some View {
        pointRow(
            id: "point.hue",
            title: "Hue",
            value: point.hueShift * 100,
            range: -100...100,
            isBipolar: true,
            gradient: EditorColorMixerStyle.hueGradient(aroundDegrees: point.referenceHue)
        ) { value in
            controller.updateSelectedPointColor { $0.hueShift = value / 100 }
        }
        pointRow(
            id: "point.saturation",
            title: "Saturation",
            value: point.saturationShift * 100,
            range: -100...100,
            isBipolar: true,
            gradient: EditorColorMixerStyle.saturationGradient(aroundDegrees: point.referenceHue)
        ) { value in
            controller.updateSelectedPointColor { $0.saturationShift = value / 100 }
        }
        pointRow(
            id: "point.luminance",
            title: "Luminance",
            value: point.luminanceShift * 100,
            range: -100...100,
            isBipolar: true,
            gradient: EditorColorMixerStyle.luminanceGradient(aroundDegrees: point.referenceHue)
        ) { value in
            controller.updateSelectedPointColor { $0.luminanceShift = value / 100 }
        }
        pointRow(
            id: "point.range",
            title: "Range",
            value: point.range * 100,
            range: 0...100,
            isBipolar: false,
            gradient: nil
        ) { value in
            controller.updateSelectedPointColor { $0.range = value / 100 }
        }
        HStack {
            Spacer()
            Button("Delete Point") {
                if let id = controller.selectedPointColorID {
                    controller.removePointColor(id: id)
                }
            }
            .buttonStyle(EditorTextButtonStyle())
        }
        .padding(.horizontal, 14)
    }

    private func pointRow(
        id: String,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        isBipolar: Bool,
        gradient: LinearGradient?,
        write: @escaping (Double) -> Void
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: value,
            range: range,
            isBipolar: isBipolar,
            valueText: isBipolar
                ? EditorColorFormat.signed(value)
                : "\(Int(value.rounded()))",
            isActive: chrome.activePlainSliderID == id,
            detent: isBipolar ? 0 : nil,
            trackGradient: gradient,
            onBeginDrag: {
                controller.beginContinuousChange()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chrome.activePlainSliderID = id
            },
            onDrag: write,
            onEndDrag: {
                controller.endContinuousChange()
                chrome.activePlainSliderID = nil
            },
            onReset: { write(isBipolar ? 0 : 50) }
        )
    }
}

// MARK: - Grading

struct EditorColorGradingSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                regionSelector
                // 28c Grade is three rows per region — Hue / Saturation / Luminance —
                // not a tint wheel: the whole panel is one row language now, and the
                // wheel needed height the fixed 246pt slab does not have. Hue and
                // Saturation write through the same `setGradingHueSat` the wheel did.
                gradingRow(
                    id: "grading.hue",
                    title: "Hue",
                    value: controller.gradingWheel(chrome.gradingRegion).hue,
                    range: 0...360,
                    isBipolar: false,
                    gradient: EditorColorMixerStyle.fullHueGradient,
                    valueText: "\(Int(controller.gradingWheel(chrome.gradingRegion).hue.rounded()))°",
                    resetValue: 0
                ) { value in
                    controller.setGradingHueSat(
                        region: chrome.gradingRegion,
                        hue: value,
                        saturation: controller.gradingWheel(chrome.gradingRegion).saturation
                    )
                }
                gradingRow(
                    id: "grading.saturation",
                    title: "Saturation",
                    value: controller.gradingWheel(chrome.gradingRegion).saturation * 100,
                    range: 0...100,
                    isBipolar: false,
                    gradient: EditorColorMixerStyle.saturationGradient(
                        aroundDegrees: controller.gradingWheel(chrome.gradingRegion).hue
                    ),
                    resetValue: 0
                ) { value in
                    controller.setGradingHueSat(
                        region: chrome.gradingRegion,
                        hue: controller.gradingWheel(chrome.gradingRegion).hue,
                        saturation: value / 100
                    )
                }
                gradingRow(
                    id: "grading.luminance",
                    title: "Luminance",
                    value: controller.gradingWheel(chrome.gradingRegion).luminance * 100,
                    range: -100...100,
                    isBipolar: true,
                    gradient: EditorColorMixerStyle.neutralLuminanceGradient
                ) { value in
                    controller.setGradingLuminance(region: chrome.gradingRegion, value / 100)
                }
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
                gradingRow(
                    id: "grading.blending",
                    title: "Blending",
                    value: controller.recipe.color.grading.blending * 100,
                    range: 0...100,
                    isBipolar: false,
                    gradient: nil
                ) { value in
                    controller.setGradingBlending(value / 100)
                }
                gradingRow(
                    id: "grading.balance",
                    title: "Balance",
                    value: controller.recipe.color.grading.balance * 100,
                    range: -100...100,
                    isBipolar: true,
                    gradient: EditorColorMixerStyle.balanceGradient
                ) { value in
                    controller.setGradingBalance(value / 100)
                }
                Color.clear.frame(height: 12)
            }
            .padding(.top, 6)
        }
        .scrollDisabled(chrome.activePlainSliderID != nil)
    }

    /// Region picker in the same capsule-chip language as the Filters and Crop
    /// strips — a horizontal `EditorChipButtonStyle` strip, accent when selected —
    /// instead of the old dot-over-caption buttons that read as a different control
    /// from every other tab. Natural-width chips in a horizontal scroll, exactly
    /// like `EditorFiltersPanel.categoryStrip`; the four fit a phone without
    /// scrolling and larger Dynamic Type scrolls rather than truncating. The
    /// per-region tint stays on as a small leading dot inside each chip, so the
    /// readout the wheel writes is not lost.
    private var regionSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ColorGradingRegion.allCases) { region in
                    let isSelected = chrome.gradingRegion == region
                    Button {
                        withAnimation(EditorTheme.animation) {
                            chrome.gradingRegion = region
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(EditorColorMixerStyle.regionTint(
                                    controller.gradingWheel(region)
                                ))
                                .frame(width: 10, height: 10)
                                .overlay {
                                    Circle().strokeBorder(
                                        Color.white.opacity(0.3),
                                        lineWidth: 0.5
                                    )
                                }
                            Text(region.displayName)
                        }
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
                    .accessibilityLabel(region.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func gradingRow(
        id: String,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        isBipolar: Bool,
        gradient: LinearGradient?,
        valueText: String? = nil,
        resetValue: Double? = nil,
        write: @escaping (Double) -> Void
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: value,
            range: range,
            isBipolar: isBipolar,
            valueText: valueText
                ?? (isBipolar
                    ? EditorColorFormat.signed(value)
                    : "\(Int(value.rounded()))"),
            isActive: chrome.activePlainSliderID == id,
            detent: isBipolar ? 0 : nil,
            trackGradient: gradient,
            onBeginDrag: {
                controller.beginContinuousChange()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chrome.activePlainSliderID = id
            },
            onDrag: write,
            onEndDrag: {
                controller.endContinuousChange()
                chrome.activePlainSliderID = nil
            },
            onReset: { write(resetValue ?? (isBipolar ? 0 : 50)) }
        )
    }
}

// MARK: - Formatting + gradients

enum EditorColorFormat {
    static func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

/// Track gradients and swatch colors for the Color tab. Hues come from
/// `ColorMixerBand.centerDegrees`, the same constants the render kernels use.
enum EditorColorMixerStyle {
    static func hueColor(
        _ degrees: Double,
        saturation: Double = 1,
        brightness: Double = 1
    ) -> Color {
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        return Color(hue: wrapped / 360, saturation: saturation, brightness: brightness)
    }

    static func gradient(band: ColorMixerBand, property: ColorMixerProperty) -> LinearGradient {
        switch property {
        case .hue:
            hueGradient(aroundDegrees: band.centerDegrees)
        case .saturation:
            saturationGradient(aroundDegrees: band.centerDegrees)
        case .luminance:
            luminanceGradient(aroundDegrees: band.centerDegrees)
        }
    }

    /// What the slider can shift the band toward: ±30°, halfway to the
    /// neighboring bands.
    static func hueGradient(aroundDegrees center: Double) -> LinearGradient {
        LinearGradient(
            colors: [-30.0, -15, 0, 15, 30].map { hueColor(center + $0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func saturationGradient(aroundDegrees center: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                hueColor(center, saturation: 0.05, brightness: 0.65),
                hueColor(center, saturation: 1, brightness: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func luminanceGradient(aroundDegrees center: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                hueColor(center, saturation: 0.85, brightness: 0.22),
                hueColor(center, saturation: 0.45, brightness: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static let neutralLuminanceGradient = LinearGradient(
        colors: [Color(white: 0.1), Color(white: 0.95)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// The whole hue wheel laid out flat, for the Grade Hue row.
    static let fullHueGradient = LinearGradient(
        colors: stride(from: 0.0, through: 360, by: 30).map {
            hueColor($0, saturation: 0.9)
        },
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Reads as "toward shadows / toward highlights".
    static let balanceGradient = LinearGradient(
        colors: [Color(white: 0.25), Color(white: 0.9)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func referenceColor(of point: PointColorAdjustment) -> Color {
        let rgb = ColorRenderMath.rgb(from: ColorRenderMath.HSV(
            hue: point.referenceHue,
            saturation: point.referenceSaturation,
            value: point.referenceValue
        ))
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// The region dot doubles as its state readout: the current tint, or a
    /// neutral gray while the wheel sits at the center.
    static func regionTint(_ wheel: ColorGradingAdjustments.Wheel) -> Color {
        guard wheel.saturation > 0.01 else { return Color(white: 0.4) }
        return hueColor(
            wheel.hue,
            saturation: wheel.saturation * 0.9 + 0.1,
            brightness: 0.9
        )
    }
}
