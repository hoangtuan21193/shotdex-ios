import SwiftUI
import UIKit
import ShotDexKit

// The Color tool used to be one tab behind a Mixer | Point Color | Grading
// section picker; it is now three sibling tabs (`PhotoEditorTool.colorMixer` /
// `.pointColor` / `.colorGrading`), so each block is one tap and owns the whole
// panel. `PhotoEditorScreen.toolPanel` renders one of the three section views
// below directly — there is no wrapper and no picker.

// MARK: - Mixer

struct EditorColorMixerSection: View {
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    /// Every channel's HUE / SAT / LUM in one scroll, grouped under three sticky
    /// section labels. No channel-picker strip: each row's track is already tinted
    /// the way that channel shifts, so the colour is the label.
    ///
    /// The wide sidebar takes Lightroom's arrangement instead — a row of eight
    /// band swatches and then that band's three sliders. Twenty-four rows is
    /// taller than the panel, so the all-channels list can only be read by
    /// scrolling it; picking the band first turns it into three rows that are
    /// all on screen at once, which is how a hue is actually adjusted. The
    /// list is still there under the "All" swatch, and is still the only mode
    /// on the phone, where a swatch row would cost a slider.
    var body: some View {
        if chrome.isWideLayout {
            bandedMix
        } else if let band = chrome.sidebarMixBand {
            // Phone with a band picked in the target strip: that band's three rows.
            VStack(spacing: 0) {
                ForEach(ColorMixerProperty.allCases) { property in
                    mixerRow(band: band, property: property, title: property.displayName)
                }
                Spacer(minLength: 0)
            }
        } else {
            allChannelsScroll
        }
    }

    /// Bands holding a shift on this photo — spoken as "Edited" on each swatch.
    static func editedBands(of controller: PhotoEditorController) -> Set<ColorMixerBand> {
        let mixer = controller.recipe.color.mixer
        return Set(ColorMixerBand.allCases.filter { !mixer[$0].isIdentity })
    }

    // MARK: Banded (wide sidebar)

    private var bandedMix: some View {
        VStack(spacing: 0) {
            EditorColorMixBandPicker(
                selection: chrome.sidebarMixBand,
                editedBands: editedBands
            ) { band in
                chrome.sidebarMixBand = band
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.sm)

            if let band = chrome.sidebarMixBand {
                ForEach(ColorMixerProperty.allCases) { property in
                    mixerRow(band: band, property: property, title: property.displayName)
                }
            } else {
                mixerRows
            }
        }
    }

    /// Bands holding a shift on this photo, for the swatch's ring.
    private var editedBands: Set<ColorMixerBand> {
        Self.editedBands(of: controller)
    }

    private var allChannelsScroll: some View {
        mixerRows
            .editorPanelScroll(panelScrolls)
            .scrollDisabled(chrome.activePlainSliderID != nil)
            .overlay(alignment: .bottom) {
                if panelScrolls {
                    LinearGradient(
                        colors: [EditorTheme.panel.opacity(0), EditorTheme.panel],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                    .allowsHitTesting(false)
                }
            }
    }

    private var mixerRows: some View {
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
                            isFirst: property == ColorMixerProperty.allCases.first
                        )
                    }
                }
            Color.clear.frame(height: 16)
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
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        if chrome.isWideLayout {
            stackedBody
        } else {
            phoneBody
        }
    }

    /// Phone (FS-03.12): the swatches and the eyedropper are the target strip
    /// (`EditorPointColorStrip`). With no point yet there is no strip — the zone is
    /// a 40pt eyedropper disc over one line, and the photo is already armed, so the
    /// first tap on it is the pick.
    @ViewBuilder
    private var phoneBody: some View {
        if controller.pointColors.isEmpty {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(EditorTheme.trackChip, in: Circle())
                    .accessibilityHidden(true)
                Text("Tap the photo to pick a color, then adjust only that color")
                    .font(.system(size: 13))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if controller.canAddPointColor { chrome.isEyedropperActive = true }
            }
        } else {
            VStack(spacing: 0) {
                if let point = controller.selectedPointColor {
                    pointSliders(point)
                }
                Color.clear.frame(height: 16)
            }
            .editorPanelScroll(panelScrolls)
            .scrollDisabled(chrome.activePlainSliderID != nil)
        }
    }

    private var stackedBody: some View {
        VStack(spacing: 0) {
            swatchRow
                .padding(.top, 6)
            VStack(spacing: 0) {
                    if let point = controller.selectedPointColor {
                        pointSliders(point)
                    } else {
                        // Describes the state the user is actually in. Until
                        // the eyedropper is armed a drag on the photo pans and
                        // zooms it, so an instruction to drag on the photo was
                        // a step ahead of itself; once armed, the on-photo pill
                        // says the rest.
                        Text(
                            chrome.isEyedropperActive
                                ? "Drag on the photo — the loupe shows the pixel under your finger. Lift to pick it."
                                : "Tap Pick a Color, then drag on the photo to choose one."
                        )
                            .font(EditorTheme.rowLabel)
                            .foregroundStyle(EditorTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 40)
                    }
                    Color.clear.frame(height: 16)
            }
            .editorPanelScroll(panelScrolls)
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
        HStack(spacing: 8) {
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
            HStack(spacing: 8) {
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
            if chrome.isWideLayout {
                Button("Delete Point") {
                    if let id = controller.selectedPointColorID {
                        controller.removePointColor(id: id)
                    }
                }
                .buttonStyle(EditorTextButtonStyle())
            } else {
                Button {
                    if let id = controller.selectedPointColorID {
                        controller.removePointColor(id: id)
                    }
                } label: {
                    EditorPanelChipLabel(title: "Delete Point", systemImage: "trash")
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
            }
        }
        .padding(.horizontal, chrome.isWideLayout ? 14 : AppTheme.Spacing.lg)
        .frame(minHeight: chrome.isWideLayout ? 0 : EditorLayoutMetrics.editorPanelRowHeight)
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
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        // Phone: rows sit on the 40pt grid with nothing between them (FS-03.12).
        VStack(spacing: chrome.isWideLayout ? 8 : 0) {
                // The region picker moved to the panel's target strip (30c), so the
                // scroll is just the rows for whichever region is selected there.
                // Grade is three rows per region — Hue / Saturation / Luminance —
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
                if chrome.isWideLayout {
                    Rectangle()
                        .fill(EditorTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                }
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
        .padding(.top, chrome.isWideLayout ? 6 : 0)
        .editorPanelScroll(panelScrolls)
        .scrollDisabled(chrome.activePlainSliderID != nil)
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

/// Grade's target strip: which tonal region — Shadow / Mid / Highlight / Global —
/// the Hue / Saturation / Luminance rows below act on. Lives at the top of the
/// panel, touching the photo, because it names an area the grade applies to.
/// Capsule-chip language shared with the Filters and Crop strips, each chip
/// carrying a leading dot in the region's current tint so the readout is not lost.
/// The phone panel's Point Color target strip: one 20pt swatch per sampled point
/// (white ring on the selected one) and the eyedropper chip at the end, white 20%
/// while armed. Long-press a swatch to delete it.
struct EditorPointColorStrip: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        let isEnabled = controller.canAddPointColor || chrome.isEyedropperActive
        HStack(spacing: EditorStripLayout.chipSpacing) {
            ForEach(controller.pointColors) { point in
                let isSelected = controller.selectedPointColorID == point.id
                Button {
                    controller.selectedPointColorID = point.id
                    chrome.isEyedropperActive = false
                } label: {
                    Circle()
                        .fill(EditorColorMixerStyle.referenceColor(of: point))
                        .frame(width: 20, height: 20)
                        .padding(2)
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(.white, lineWidth: 1.5)
                            }
                        }
                        .opacity(isSelected ? 1 : EditorTheme.swatchIdle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            Button {
                withAnimation(EditorTheme.animation) {
                    chrome.isEyedropperActive.toggle()
                }
            } label: {
                Image(systemName: "eyedropper")
                    .frame(width: 24)
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: chrome.isEyedropperActive))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : EditorTheme.rowDisabled)
            .accessibilityLabel("Sample a color")
            .accessibilityValue(chrome.isEyedropperActive ? "Armed" : "Off")
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EditorGradeRegionStrip: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        EditorPanelChipStrip(
            items: ColorGradingRegion.allCases,
            isSelected: { chrome.gradingRegion == $0 },
            label: { EditorPanelChipLabel(title: $0.displayName, systemImage: $0.stripSymbol) },
            accessibilityName: \.displayName,
            onSelect: { region in
                withAnimation(EditorTheme.animation) { chrome.gradingRegion = region }
            }
        )
    }
}

extension ColorGradingRegion {
    /// Half-filled circle, circle with a dot, sun, globe — the tonal band read as a
    /// shape rather than as the tint the region carries (FS-03.12 drops the tint dot).
    var stripSymbol: String {
        switch self {
        case .shadows: "circle.lefthalf.filled"
        case .midtones: "smallcircle.filled.circle"
        case .highlights: "sun.max"
        case .global: "globe"
        }
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


/// The eight colour bands as swatches, plus an "All" stop that falls back to the
/// full twenty-four-row list.
///
/// Circles rather than chips because the thing being picked *is* a colour: a
/// word ("Aqua") has to be read, a swatch is recognised. The selected one is
/// ringed rather than enlarged, so the row does not reflow as the selection
/// moves, and a band that already holds a shift keeps a small dot — otherwise
/// the only way to find an edit made earlier is to tap all eight.
struct EditorColorMixBandPicker: View {
    let selection: ColorMixerBand?
    let editedBands: Set<ColorMixerBand>
    /// The phone panel draws no visible "edited" dot (FS-03.12 §6); VoiceOver still
    /// says "Edited".
    var showsEditedMarks = true
    var rowHeight: CGFloat = AppTheme.Size.minTouch
    var select: (ColorMixerBand?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ColorMixerBand.allCases) { band in
                swatch(
                    fill: AnyShapeStyle(
                        EditorColorMixerStyle.hueColor(band.centerDegrees)
                    ),
                    isSelected: selection == band,
                    hasEdits: editedBands.contains(band),
                    label: band.displayName
                ) {
                    select(band)
                }
            }

            swatch(
                fill: AnyShapeStyle(EditorTheme.control),
                isSelected: selection == nil,
                hasEdits: false,
                label: "All Colors",
                glyph: "circle.hexagongrid"
            ) {
                select(nil)
            }
        }
        .frame(height: rowHeight)
    }

    private func swatch(
        fill: AnyShapeStyle,
        isSelected: Bool,
        hasEdits: Bool,
        label: String,
        glyph: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(
                        width: EditorLayoutMetrics.sidebarSwatchDiameter,
                        height: EditorLayoutMetrics.sidebarSwatchDiameter
                    )
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                if hasEdits, !isSelected, showsEditedMarks {
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .offset(y: EditorLayoutMetrics.sidebarSwatchDiameter / 2 + 4)
                }
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(
                            width: EditorLayoutMetrics.sidebarSwatchDiameter + 8,
                            height: EditorLayoutMetrics.sidebarSwatchDiameter + 8
                        )
                }
            }
            // The row seats nine items in as little as 248pt, so each one takes
            // an equal share and the gaps close rather than the circles
            // shrinking — a swatch below about 20pt stops reading as a colour.
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityValue(hasEdits ? "Edited" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
