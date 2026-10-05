import ShotDexKit
import SwiftUI

/// The Watermark screen (FS-05.04 §4) — tier D, dark, pushed from a form's
/// Watermark row, Done top right. One configuration for every form.
///
/// - Phone 402×874 and the Duo's cover (382pt after its rail): preview on
///   top (320pt; 240 on the cover), controls scrolling underneath.
/// - Duo inner 951×669: preview left, a 320pt control column right.
/// - iPad: the Mac-style tool frame — header row, preview left, a 360pt
///   inspector right, a filmstrip under a landscape preview.
struct WatermarkScreen: View {
    @Bindable var model: WatermarkModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @State private var isTypingSize = false
    @State private var typedSize = ""

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad, size.width >= 700 {
                    padLayout(size)
                } else if size.width >= 700 {
                    wideLayout(size)
                } else {
                    compactLayout(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .background(EditorTheme.panelSolid.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert(WatermarkCopy.sizeInPixels(), isPresented: $isTypingSize) {
            TextField(WatermarkCopy.pixels(), text: $typedSize)
                .keyboardType(.numberPad)
            Button(WatermarkCopy.set()) {
                if let pixels = Int(typedSize.trimmingCharacters(in: .whitespaces)) { model.setSizePixels(pixels) }
            }
            Button(WatermarkCopy.cancel(), role: .cancel) {}
        }
    }

    // MARK: Layouts

    private func compactLayout(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            header
            WatermarkPreviewPager(model: model, pill: true)
                .frame(height: size.height < 700 ? 240 : 320)
                .background(Color.black)
            ScrollView {
                controls
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, 14)
            }
        }
    }

    private func wideLayout(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                WatermarkPreviewPager(model: model, pill: true)
                    .background(Color.black)
                Rectangle().fill(EditorTheme.panelDivider).frame(width: 1)
                ScrollView {
                    controls
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
                .frame(width: 320)
            }
        }
    }

    /// The bar every phone layout shares: back to the form, the title, Done.
    private var header: some View {
        ZStack {
            Text(WatermarkCopy.watermark())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        Text(model.formTitle).font(.system(size: 16))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.formTitle)
                Spacer()
                doneButton(height: 36)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(height: 52)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .bottom) { Rectangle().fill(EditorTheme.hairline).frame(height: 0.5) }
    }

    private func doneButton(height: CGFloat) -> some View {
        Button { dismiss() } label: {
            Text(WatermarkCopy.done())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(height: height)
                .background(accent, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Phone controls

    @ViewBuilder
    private var controls: some View {
        if model.hasPresets {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })) {
                    Text(WatermarkCopy.addWatermark())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .tint(accent)
                .frame(minHeight: 44)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    CompressionGroupLabel(text: WatermarkCopy.watermark())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(model.presets.presets) { preset in presetChip(preset) }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        CompressionGroupLabel(text: WatermarkCopy.position()).frame(width: 120, alignment: .leading)
                        positionGrid(cell: CGSize(width: 36, height: 36), gap: 6, radius: AppTheme.Radius.sm)
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        CompressionGroupLabel(text: WatermarkCopy.size())
                        sizeStepper
                        Text(WatermarkCopy.percentOfShortSide(model.sizeFraction))
                            .font(.system(size: 12))
                            .foregroundStyle(EditorTheme.dimText.opacity(1.3))
                    }
                }

                slider(WatermarkCopy.margin(), value: model.placement.margin, range: WatermarkPlacement.marginRange, reset: 0.03, set: model.setMargin)
                slider(WatermarkCopy.opacity(), value: model.placement.opacity, range: WatermarkPlacement.opacityRange, reset: 1, set: model.setOpacity)
            }
            .disabled(false)
        } else {
            WatermarkEmptyState()
        }
    }

    private func presetChip(_ preset: SignaturePreset) -> some View {
        let selected = model.isEnabled && model.selectedPreset?.id == preset.id
        let availability = model.availability(of: preset)
        return Button {
            model.choose(preset)
        } label: {
            VStack(spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? .white : .white.opacity(0.85))
                Text(WatermarkCopy.chipDetail(preset, availability: availability))
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
        .buttonStyle(CompressionChoiceStyle(selected: selected, accent: accent))
        .disabled(!availability.isSelectable)
        .opacity(availability.isSelectable ? 1 : 0.45)
        .accessibilityLabel(WatermarkScreen.presetLabel(preset, availability))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// `Logo, Missing file` — the chip's name and why it is limited.
    static func presetLabel(_ preset: SignaturePreset, _ availability: WatermarkAvailability) -> String {
        switch availability {
        case .available: preset.name
        case .missingFile: "\(preset.name), \(WatermarkCopy.missingFile())"
        case .fontUnavailable: "\(preset.name), \(WatermarkCopy.unavailable())"
        }
    }

    private func positionGrid(cell: CGSize, gap: CGFloat, radius: CGFloat) -> some View {
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(WatermarkAnchor.allCases.filter { $0.row == row }) { anchor in
                        let selected = model.placement.anchor == anchor
                        Button {
                            model.setAnchor(anchor)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .fill(selected ? accent.opacity(0.22) : EditorTheme.control)
                                RoundedRectangle(cornerRadius: selected ? 3 : 3, style: .continuous)
                                    .fill(selected ? accent : EditorTheme.dimText)
                                    .frame(width: selected ? 12 : 6, height: selected ? 12 : 6)
                            }
                            .frame(width: cell.width, height: cell.height)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WatermarkCopy.positionLabel(anchor))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WatermarkCopy.position())
    }

    private var sizeStepper: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            stepButton("−", label: WatermarkCopy.smaller()) { model.stepSize(by: -1) }
            Button {
                typedSize = "\(model.sizePixels)"
                isTypingSize = true
            } label: {
                Text(WatermarkCopy.pixelValue(model.sizePixels))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 74, minHeight: 44)
                    .background(EditorTheme.panel, in: RoundedRectangle.app(AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WatermarkCopy.size())
            .accessibilityValue(WatermarkCopy.pixelValue(model.sizePixels))
            .accessibilityAdjustableAction { direction in
                model.stepSize(by: direction == .increment ? 1 : -1)
            }
            stepButton("+", label: WatermarkCopy.larger()) { model.stepSize(by: 1) }
        }
        .disabled(!model.isEnabled)
    }

    private func stepButton(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func slider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        reset: Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        EditorValueSlider(
            label: label,
            value: value,
            range: range,
            valueText: "\(Int((value * 100).rounded()))%",
            accessibilityName: label,
            onBeginDrag: {},
            onDrag: set,
            onReset: { set(reset) }
        )
        .environment(\.editorSliderStacked, true)
        .padding(.horizontal, -AppTheme.Spacing.lg)
    }

    // MARK: iPad

    private func padLayout(_ size: CGSize) -> some View {
        let landscape = size.width >= 1100
        let inspectorWidth: CGFloat = 360
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                padHeader(landscape: landscape)
                WatermarkPreviewPager(model: model, pill: false)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                if model.pages.count > 1 {
                    if landscape {
                        WatermarkFilmstrip(model: model)
                            .frame(height: 100)
                    } else {
                        Text(WatermarkCopy.pageCounter(model.currentIndex + 1, of: model.pages.count))
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(EditorTheme.secondaryText)
                            .padding(.vertical, AppTheme.Spacing.lg)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)
            WatermarkInspector(
                model: model, accent: accent, isPortrait: !landscape,
                isTypingSize: $isTypingSize, typedSize: $typedSize
            ) {
                dismiss()
            }
            .frame(width: inspectorWidth)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func padHeader(landscape: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text(model.formTitle).font(.system(size: 17, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(height: 44)
                .editorGlass(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WatermarkCopy.backTo(model.formTitle))
            VStack(alignment: .leading, spacing: 2) {
                Text(WatermarkCopy.watermark())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text(WatermarkCopy.padSubtitle(form: model.formTitle, count: model.pages.count, index: model.currentIndex + 1))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, 32)
        .padding(.bottom, AppTheme.Spacing.md)
    }
}

/// The iPad inspector (board `IP22_Watermark`): Done on top, then the
/// Watermark section — Add Watermark and the presets as rows — and the
/// Placement section — Position, Size, Margin, Opacity.
private struct WatermarkInspector: View {
    @Bindable var model: WatermarkModel
    let accent: Color
    /// Board `IPP18_Watermark`: the switch above the sections, and Position
    /// and Size as sections of their own; landscape (`IP22`) groups them
    /// under Placement.
    let isPortrait: Bool
    @Binding var isTypingSize: Bool
    @Binding var typedSize: String
    let done: () -> Void

    @State private var showsPresets = true
    @State private var showsPlacement = true
    @State private var showsPosition = true
    @State private var showsSize = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: done) {
                    Text(WatermarkCopy.done())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, 32)
            .padding(.bottom, AppTheme.Spacing.lg)
            ScrollView {
                if model.hasPresets, isPortrait {
                    portraitSections
                } else if model.hasPresets {
                    VStack(spacing: 0) {
                        section(WatermarkCopy.watermark(), isOpen: $showsPresets) {
                            enabledSwitch
                            VStack(spacing: 0) {
                                ForEach(model.presets.presets) { presetRow($0) }
                            }
                            .padding(.horizontal, AppTheme.Spacing.sm)
                        }
                        Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
                        section(WatermarkCopy.placement(), isOpen: $showsPlacement) {
                            placement
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.xl)
                } else {
                    WatermarkEmptyState().padding(AppTheme.Spacing.lg)
                }
            }
        }
        .background(EditorTheme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(EditorTheme.panelDivider).frame(width: 1) }
    }

    private var enabledSwitch: some View {
        Toggle(isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) })) {
            Text(WatermarkCopy.addWatermark()).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        }
        .tint(accent)
        .frame(minHeight: 44)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(EditorTheme.panelDivider).frame(height: 1)
    }

    private var portraitSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            enabledSwitch.padding(.bottom, 12)
            divider
            section(WatermarkCopy.watermark(), isOpen: $showsPresets) {
                VStack(spacing: 2) {
                    ForEach(model.presets.presets) { presetRow($0) }
                }
                .padding(.leading, AppTheme.Spacing.sm)
                .padding(.trailing, AppTheme.Spacing.lg)
            }
            divider
            section(WatermarkCopy.position(), isOpen: $showsPosition) {
                anchorGrid(cell: CGSize(width: 64, height: 44), gap: 8)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            divider
            section(WatermarkCopy.size(), isOpen: $showsSize) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        sizeField(width: 96)
                        chevronStep("chevron.down", label: WatermarkCopy.smaller()) { model.stepSize(by: -1) }
                        Rectangle().fill(EditorTheme.hairline).frame(width: 1, height: 44)
                        chevronStep("chevron.up", label: WatermarkCopy.larger()) { model.stepSize(by: 1) }
                    }
                    .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
                    .clipShape(RoundedRectangle.app(AppTheme.Radius.md))
                    .disabled(!model.isEnabled)
                    Text(WatermarkCopy.percentOfShortSide(model.sizeFraction))
                        .font(.system(size: 15))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            inlineSlider(WatermarkCopy.margin(), value: model.placement.margin, range: WatermarkPlacement.marginRange, set: model.setMargin)
            inlineSlider(WatermarkCopy.opacity(), value: model.placement.opacity, range: WatermarkPlacement.opacityRange, set: model.setOpacity)
        }
        .padding(.bottom, AppTheme.Spacing.xl)
    }

    private func sizeField(width: CGFloat) -> some View {
        Button {
            typedSize = "\(model.sizePixels)"
            isTypingSize = true
        } label: {
            Text(WatermarkCopy.pixelValue(model.sizePixels))
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: width - 20, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(EditorTheme.panel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WatermarkCopy.size())
        .accessibilityValue(WatermarkCopy.pixelValue(model.sizePixels))
    }

    private func chevronStep(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func anchorGrid(cell: CGSize, gap: CGFloat) -> some View {
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(WatermarkAnchor.allCases.filter { $0.row == row }) { anchor in
                        anchorCell(anchor, size: cell)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WatermarkCopy.position())
    }

    private func section<Content: View>(
        _ title: String,
        isOpen: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EditorTheme.animation) { isOpen.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 0 : -90))
                        .frame(width: 16, height: 48)
                        .foregroundStyle(EditorTheme.secondaryText)
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                }
                .frame(height: 48)
                .padding(.leading, 12)
                .padding(.trailing, AppTheme.Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen.wrappedValue ? WatermarkCopy.collapse(title) : WatermarkCopy.expand(title))
            if isOpen.wrappedValue { content() }
        }
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    private func presetRow(_ preset: SignaturePreset) -> some View {
        let selected = model.isEnabled && model.selectedPreset?.id == preset.id
        let availability = model.availability(of: preset)
        return Button {
            model.choose(preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.name).font(.system(size: 17)).foregroundStyle(.white)
                    Text(WatermarkCopy.chipDetail(preset, availability: availability))
                        .font(.system(size: 13))
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                Spacer(minLength: 0)
                if !availability.isSelectable {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(height: 52)
            .background(selected ? EditorTheme.chipSelected.opacity(0.6) : .clear, in: RoundedRectangle.app(AppTheme.Radius.md))
            .contentShape(Rectangle())
            .opacity(availability.isSelectable ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!availability.isSelectable)
        .accessibilityLabel(WatermarkScreen.presetLabel(preset, availability))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var placement: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                anchorGrid(cell: CGSize(width: 52, height: 44), gap: 6)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(WatermarkCopy.size()).font(.system(size: 17)).foregroundStyle(.white)
                    Button {
                        typedSize = "\(model.sizePixels)"
                        isTypingSize = true
                    } label: {
                        Text(WatermarkCopy.pixelValue(model.sizePixels))
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
                            .overlay(RoundedRectangle.app(AppTheme.Radius.md).stroke(EditorTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(WatermarkCopy.size())
                    .accessibilityValue(WatermarkCopy.pixelValue(model.sizePixels))
                    HStack(spacing: 0) {
                        stepButton("minus", label: WatermarkCopy.smaller()) { model.stepSize(by: -1) }
                        Rectangle().fill(EditorTheme.hairline).frame(width: 1, height: 20)
                        stepButton("plus", label: WatermarkCopy.larger()) { model.stepSize(by: 1) }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 44)
                    .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.md))
                }
                .disabled(!model.isEnabled)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            Text(WatermarkCopy.percentOfShortSide(model.sizeFraction))
                .font(.system(size: 13))
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, AppTheme.Spacing.lg)
            inlineSlider(WatermarkCopy.margin(), value: model.placement.margin, range: WatermarkPlacement.marginRange, set: model.setMargin)
            inlineSlider(WatermarkCopy.opacity(), value: model.placement.opacity, range: WatermarkPlacement.opacityRange, set: model.setOpacity)
        }
    }

    private func anchorCell(_ anchor: WatermarkAnchor, size: CGSize) -> some View {
        let selected = model.placement.anchor == anchor
        return Button {
            model.setAnchor(anchor)
        } label: {
            ZStack {
                RoundedRectangle.app(AppTheme.Radius.md)
                    .fill(selected ? accent.opacity(0.22) : EditorTheme.control)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(selected ? accent : EditorTheme.dimText)
                    .frame(width: selected ? 14 : 6, height: selected ? 14 : 6)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WatermarkCopy.positionLabel(anchor))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Label, slider, value — the inspector row of IPAD_STYLE (row 44,
    /// label 17, value 15, the system knob).
    private func inlineSlider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 112, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range)
                .tint(Color.white.opacity(0.62))
                .accessibilityLabel(label)
                .accessibilityValue("\(Int((value * 100).rounded()))%")
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 56, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: 44)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

/// "No watermarks yet", and where to make one (FS-05.04 §5).
struct WatermarkEmptyState: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "signature")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(EditorTheme.secondaryText)
                .accessibilityHidden(true)
            Text(WatermarkCopy.noWatermarksYet())
                .font(.headline)
                .foregroundStyle(.white)
            Text(WatermarkCopy.howToMakeOne())
                .font(.subheadline)
                .foregroundStyle(EditorTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
    }
}
