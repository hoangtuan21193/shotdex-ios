import SwiftUI
import UIKit

/// The Color tool: Mixer / Point Color / Grading behind a fixed section picker.
/// The panel's content height is only ~230–280pt, so each section owns the
/// space alone instead of sharing one long scroll.
struct EditorColorPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
            switch chrome.colorSection {
            case .mixer:
                EditorColorMixerSection(controller: controller, chrome: chrome)
            case .pointColor:
                EditorPointColorSection(controller: controller, chrome: chrome)
            case .grading:
                EditorColorGradingSection(controller: controller, chrome: chrome)
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(EditorColorSection.allCases) { section in
                let isSelected = chrome.colorSection == section
                Button {
                    withAnimation(EditorTheme.animation) {
                        chrome.colorSection = section
                        chrome.isEyedropperActive = false
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Color.white : EditorTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            isSelected ? EditorTheme.accent : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(EditorTheme.control, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Mixer

private struct EditorColorMixerSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    /// All three properties in one scroll with sticky headers — the same shape
    /// as the Adjust panel. A Hue/Saturation/Luminance/All chip row on top of it
    /// spent 38pt to hide two thirds of the sliders behind a tap.
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(ColorMixerProperty.allCases) { property in
                    Section {
                        bandRows(property)
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

    @ViewBuilder
    private func bandRows(_ property: ColorMixerProperty) -> some View {
        ForEach(ColorMixerBand.allCases) { band in
            let sliderID = "mixer.\(property.rawValue).\(band.rawValue)"
            EditorPlainSliderRow(
                title: band.displayName,
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
}

// MARK: - Point Color

private struct EditorPointColorSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            swatchRow
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if let point = controller.selectedPointColor {
                        pointSliders(point)
                    } else {
                        Text("Tap the eyedropper, then tap a color in the photo")
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

    private var swatchRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(EditorTheme.animation) {
                    chrome.isEyedropperActive.toggle()
                }
            } label: {
                EditorPillLabel(
                    text: nil,
                    systemImage: "eyedropper",
                    isActive: chrome.isEyedropperActive
                )
            }
            .buttonStyle(.plain)
            .disabled(!controller.canAddPointColor && !chrome.isEyedropperActive)
            .opacity(controller.canAddPointColor || chrome.isEyedropperActive ? 1 : 0.4)
            .accessibilityLabel("Sample a color")

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
                        .accessibilityLabel("Point color")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
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

private struct EditorColorGradingSection: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                regionSelector
                EditorColorWheel(
                    hue: controller.gradingWheel(chrome.gradingRegion).hue / 360,
                    saturation: controller.gradingWheel(chrome.gradingRegion).saturation,
                    onBegin: {
                        controller.beginContinuousChange()
                        chrome.activePlainSliderID = "grading.wheel"
                    },
                    onChange: { hue, saturation in
                        controller.setGradingHueSat(
                            region: chrome.gradingRegion,
                            hue: hue * 360,
                            saturation: saturation
                        )
                    },
                    onEnd: {
                        controller.endContinuousChange()
                        chrome.activePlainSliderID = nil
                    },
                    onReset: {
                        controller.resetColorGrading(region: chrome.gradingRegion)
                    }
                )
                .padding(.top, 2)
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
        }
        .scrollDisabled(chrome.activePlainSliderID != nil)
    }

    private var regionSelector: some View {
        HStack(spacing: 6) {
            ForEach(ColorGradingRegion.allCases) { region in
                let isSelected = chrome.gradingRegion == region
                Button {
                    withAnimation(EditorTheme.animation) {
                        chrome.gradingRegion = region
                    }
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(EditorColorMixerStyle.regionTint(
                                controller.gradingWheel(region)
                            ))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? EditorTheme.accent : EditorTheme.hairline,
                                    lineWidth: isSelected ? 2 : 1
                                )
                            }
                        Text(region.displayName)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(
                                isSelected ? EditorTheme.accent : EditorTheme.secondaryText
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(region.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private func gradingRow(
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
