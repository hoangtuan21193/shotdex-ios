import SwiftUI
import ShotDexKit

/// The iPad inspector's parameter rows in the Mac style (boards IL2/IP2,
/// FS-12.03 §2, FS-12.04b §5): a 17pt label in a 96pt column, a slider
/// with a 4pt track, a white trail and a 28pt knob, the value in 15pt
/// secondary text in a 60pt column — 44 tall. The phone and the Duo keep
/// the shared `EditorValueSlider` row (`InspectorSlider`).
struct DeskSliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    /// Where the white trail starts.
    var anchor: Double?
    var labelWidth: CGFloat = DeskRowMetrics.labelWidth
    let model: VideoStudioModel
    let set: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: DeskRowMetrics.labelSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            DeskSlider(value: value, range: range, anchor: anchor ?? range.lowerBound, model: model, set: set, reset: reset)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(valueText))
            Text(valueText)
                .font(.system(size: DeskRowMetrics.valueSize).monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .frame(width: DeskRowMetrics.valueWidth, alignment: .trailing)
                .padding(.leading, DeskRowMetrics.valueGap)
                .accessibilityHidden(true)
        }
        .frame(height: DeskRowMetrics.rowHeight)
    }
}

/// The track, trail and knob. A drag is one undo step; a double tap resets.
struct DeskSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let anchor: Double
    let model: VideoStudioModel
    let set: (Double) -> Void
    let reset: () -> Void

    @State private var isDragging = false

    private func fraction(_ value: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let knob = DeskRowMetrics.knob
            let travel = max(1, proxy.size.width - knob)
            let x = knob / 2 + fraction(value) * travel
            let anchorX = knob / 2 + fraction(anchor) * travel
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(EditorTheme.sliderNeutralTrack)
                    .frame(height: DeskRowMetrics.track)
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: abs(x - anchorX), height: DeskRowMetrics.track)
                    .offset(x: min(x, anchorX))
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: x - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            model.beginUndoGroup()
                        }
                        let progress = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                        set(range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in
                        isDragging = false
                        model.endUndoGroup()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        }
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            model.pushUndo()
            switch direction {
            case .increment: set(min(range.upperBound, value + step))
            case .decrement: set(max(range.lowerBound, value - step))
            @unknown default: break
            }
        }
    }
}

/// Volume with its speaker (IL2): a 40pt round button — a 28pt disc on
/// white 10 % — then "Volume" in an 84pt column, the slider and the value.
/// Muted, the slider dims and keeps its number.
struct DeskVolumeRow: View {
    let isMuted: Bool
    let volume: Double
    let model: VideoStudioModel
    let toggleMute: () -> Void
    let set: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: DeskRowMetrics.muteDisc, height: DeskRowMetrics.muteDisc)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .frame(width: DeskRowMetrics.muteButton, height: DeskRowMetrics.muteButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? VideoStudioCopy.unmute : VideoStudioCopy.mute)
            .padding(.trailing, DeskRowMetrics.muteGap)
            DeskSliderRow(
                label: String(localized: "Volume", table: VideoStudioCopy.table, comment: "Video Studio: a clip's or a bed's own level"),
                value: volume, range: 0...1, valueText: "\(Int((volume * 100).rounded()))",
                labelWidth: DeskRowMetrics.volumeLabelWidth,
                model: model, set: set, reset: reset
            )
            .opacity(isMuted ? 0.3 : 1)
        }
        .frame(height: DeskRowMetrics.rowHeight)
    }
}

/// 0.5× · 1× · 2× · 4× as a segmented control (IL2 "Speed Presets"): four
/// 32pt segments in a 36pt well, r12, the chosen one raised.
struct DeskSpeedPresets: View {
    let speed: Double?
    let choose: (Double) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VideoClipPanelSections.speedPresets, id: \.self) { preset in
                let isOn = speed.map { abs($0 - preset) < 0.001 } ?? false
                Button { choose(preset) } label: {
                    Text(preset.formatted(.number.precision(.significantDigits(1...2))) + "×")
                        .font(.system(size: 15, weight: isOn ? .semibold : .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? Color.white.opacity(0.22) : .clear)
                                .shadow(color: .black.opacity(isOn ? 0.3 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: DeskRowMetrics.segmentedHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Speed Presets", tableName: VideoStudioCopy.table, comment: "Video Studio iPad: the 0.5× 1× 2× 4× segmented control under the Speed slider"))
    }
}

/// IL2 / IP2's row geometry.
enum DeskRowMetrics {
    static let rowHeight: CGFloat = 44
    static let labelWidth: CGFloat = 96
    static let volumeLabelWidth: CGFloat = 84
    static let valueWidth: CGFloat = 60
    static let valueGap: CGFloat = 4
    static let labelSize: CGFloat = 17
    static let valueSize: CGFloat = 15
    static let track: CGFloat = 4
    static let knob: CGFloat = 28
    static let muteButton: CGFloat = 40
    static let muteDisc: CGFloat = 28
    /// From the button to "Volume": the label sits at 56 from the column.
    static let muteGap: CGFloat = 6
    static let segmentedHeight: CGFloat = 36
    /// From the command row's divider to the first row: 8 on the board,
    /// 3 under the scroll view's own top.
    static let firstRowTop: CGFloat = 3
    /// Section headers ("Fade", "Motion"): 15pt semibold, 28 tall.
    static let headerSize: CGFloat = 15
    static let headerHeight: CGFloat = 28
}

/// A caption's colours on the iPad (IL3/IP3): seven 44pt targets — White,
/// Black, four tints, Custom Color — each a 30pt disc; the chosen one ringed
/// in white past a 2pt gap. Custom Color is the system picker; a colour not
/// among the six rings it.
struct DeskSwatchRow: View {
    @Bindable var model: VideoStudioModel
    let selected: OverlayColor
    /// 2 between targets in the inspector (IL3), none in the dock (IP3).
    var spacing: CGFloat = 2
    let set: (OverlayColor) -> Void

    static let swatches: [OverlayColor] = [
        .white,
        .black,
        OverlayColor(red: 0xF2 / 255, green: 0xC9 / 255, blue: 0x4C / 255),
        OverlayColor(red: 0xE8 / 255, green: 0x60 / 255, blue: 0x4C / 255),
        OverlayColor(red: 0x4F / 255, green: 0xA3 / 255, blue: 0xE0 / 255),
        OverlayColor(red: 0x7B / 255, green: 0xC4 / 255, blue: 0x7F / 255),
    ]

    /// VoiceOver's name for each of `swatches`.
    static func name(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "White", table: VideoStudioCopy.table, comment: "Video Studio Video Settings: the white background swatch")
        case 1: String(localized: "Black", table: VideoStudioCopy.table, comment: "Video Studio Video Settings: the black background swatch")
        case 2: String(localized: "Yellow", table: VideoStudioCopy.table, comment: "Video Studio iPad text inspector: the yellow caption colour")
        case 3: String(localized: "Red", table: VideoStudioCopy.table, comment: "Video Studio iPad text inspector: the red caption colour")
        case 4: String(localized: "Blue", table: VideoStudioCopy.table, comment: "Video Studio iPad text inspector: the blue caption colour")
        default: String(localized: "Green", table: VideoStudioCopy.table, comment: "Video Studio iPad text inspector: the green caption colour")
        }
    }

    private static func isClose(_ a: OverlayColor, _ b: OverlayColor) -> Bool {
        abs(a.red - b.red) < 0.02 && abs(a.green - b.green) < 0.02 && abs(a.blue - b.blue) < 0.02
    }

    private var isCustom: Bool { !Self.swatches.contains { Self.isClose($0, selected) } }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { index, color in
                let isOn = Self.isClose(color, selected)
                Button { model.pushUndo(); set(color) } label: {
                    disc(Circle().fill(Color(red: color.red, green: color.green, blue: color.blue)), isOn: isOn)
                        .overlay {
                            if color == .black { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 30, height: 30) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Self.name(index)))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            ColorPicker(selection: Binding(
                get: { Color(red: selected.red, green: selected.green, blue: selected.blue) },
                set: { picked in
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    UIColor(picked).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    set(OverlayColor(red: Double(red), green: Double(green), blue: Double(blue)))
                }
            ), supportsOpacity: false) { EmptyView() }
            .labelsHidden()
            .frame(width: 44, height: 44)
            .overlay { if isCustom { ring } }
            .accessibilityLabel(Text(VideoStudioCopy.customColour))
            .accessibilityAddTraits(isCustom ? .isSelected : [])
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    private func disc<S: View>(_ shape: S, isOn: Bool) -> some View {
        shape
            .frame(width: 30, height: 30)
            .overlay { if isOn { ring } }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// 2pt of the panel, then 2pt of white.
    private var ring: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: 38, height: 38)
    }
}
