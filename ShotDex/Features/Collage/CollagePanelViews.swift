import SwiftUI

/// Panel content for the collage editor's three groups. Built from the shared
/// editor pieces (`EditorPlainSliderRow`, `EditorChipButtonStyle`,
/// `EditorGroupHeader`) so the collage reads as the same tool family as the
/// photo editor. Sheets are raised by the screen; panels only call closures.

// MARK: - Layout

/// Layout tab, three fixed tiers summing to the 152pt content zone (§1):
/// the photo counter, the aspect chip row, the template strip.
struct CollageLayoutPanel: View {
    @Bindable var model: CollageEditorModel
    let onSavePreset: () -> Void
    let onRenamePreset: (CollagePreset) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CollageCounterRow(model: model, onSavePreset: onSavePreset)
                .frame(height: CollageMetrics.counterRowHeight)
            CollageAspectRow(model: model)
                .frame(height: CollageMetrics.aspectRowHeight)
            templateStrip
                .frame(height: CollageMetrics.templateRowHeight)
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
    }

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // User presets lead the strip (§8), always neutral — yellow is
                // reserved for the template actually applied.
                ForEach(model.presets) { preset in
                    CollagePresetChip(preset: preset)
                        .onTapGesture { model.applyPreset(preset) }
                        .contextMenu {
                            Button {
                                onRenamePreset(preset)
                            } label: {
                                Label(String(localized: "Rename"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.deletePreset(preset.id)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                }
                ForEach(model.availableTemplates) { template in
                    Button {
                        model.selectTemplate(template.id)
                    } label: {
                        CollageTemplateThumbnail(
                            template: template,
                            isSelected: model.recipe.templateID == template.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A saved preset in the template strip (§8): a neutral tile with a star badge,
/// never the accent — the accent means "template currently applied", not "saved".
struct CollagePresetChip: View {
    let preset: CollagePreset

    private let side = CollageMetrics.templateCellSize

    var body: some View {
        RoundedRectangle.app(AppTheme.Radius.md)
            .fill(Color.white.opacity(0.08))
            .frame(width: side, height: side)
            .overlay {
                Text(preset.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(4)
            }
            .overlay(
                RoundedRectangle.app(AppTheme.Radius.md).strokeBorder(EditorTheme.glassStroke, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(EditorTheme.accent)
                    .padding(3)
            }
            .accessibilityLabel(String(localized: "Preset \(preset.name)"))
    }
}

/// `[ − ] N [ + ]` on the leading edge, `☆ Save preset` on the trailing (§4).
/// − dims at the floor of the supported range; + at the ceiling. Decrement sets
/// the last photo aside rather than deleting it (the model does the move; the
/// fly-into-tray animation lands in a later phase).
private struct CollageCounterRow: View {
    @Bindable var model: CollageEditorModel
    let onSavePreset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                stepButton("minus", enabled: model.canRemoveSlot) {
                    withAnimation(EditorTheme.animation) { model.removeSlot() }
                }
                Text("\(model.slotCount)")
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 20)
                stepButton("plus", enabled: model.canAddSlot) {
                    withAnimation(EditorTheme.animation) { model.addSlot() }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: CollageMetrics.counterHeight)
            .background(RoundedRectangle.app(AppTheme.Radius.sm + 1).fill(Color.white.opacity(0.07)))

            Spacer(minLength: AppTheme.Spacing.sm)

            savePresetChip
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? .white : EditorTheme.dimText)
                .frame(width: AppTheme.Size.minTouch, height: CollageMetrics.counterHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus"
            ? String(localized: "Add photo slot")
            : String(localized: "Remove photo slot"))
    }

    private var savePresetChip: some View {
        Button(action: onSavePreset) {
            Label(String(localized: "Save preset"), systemImage: "star")
                .font(EditorTheme.pillLabel)
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(height: CollageMetrics.counterHeight)
                .overlay(
                    Capsule().strokeBorder(EditorTheme.glassStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Save preset"))
    }
}

/// Horizontal aspect chips (§5). `Custom` leads the row — an outlined chip with
/// a frame glyph, always visible without scrolling — then the named ratios.
private struct CollageAspectRow: View {
    @Bindable var model: CollageEditorModel
    @State private var isCustomPresented = false
    @State private var customWidth = "3"
    @State private var customHeight = "4"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                customChip
                ForEach(CollageAspect.allCases) { aspect in
                    Button(aspect.displayName) {
                        model.selectAspect(aspect)
                    }
                    .buttonStyle(CollageAspectChipStyle(isSelected: model.recipe.aspectPreset == aspect))
                }
            }
        }
    }

    private var customChip: some View {
        Button {
            isCustomPresented = true
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "aspectratio")
                Text("Custom")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(model.recipe.aspectPreset == nil ? EditorTheme.accent : .white)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: CollageMetrics.aspectChipHeight)
            .frame(minWidth: CollageMetrics.aspectChipMinWidth)
            .overlay(
                RoundedRectangle.app(AppTheme.Radius.sm).strokeBorder(
                    model.recipe.aspectPreset == nil ? EditorTheme.accent : EditorTheme.glassStroke,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isCustomPresented, arrowEdge: .bottom) {
            CollageCustomAspectPopover(
                model: model,
                width: $customWidth,
                height: $customHeight,
                dismiss: { isCustomPresented = false }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Aspect chip: centred uppercase label, equal minimum width so a long name and
/// a short one sit the same size (§5).
private struct CollageAspectChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: CollageMetrics.aspectChipHeight)
            .frame(minWidth: CollageMetrics.aspectChipMinWidth)
            .background(
                RoundedRectangle.app(AppTheme.Radius.sm)
                    .fill(isSelected ? EditorTheme.accent : Color.white.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Custom-ratio popover (§5): W : H fields with a swap, four shortcuts, and a
/// yellow Apply. The frame previews on every keystroke; Apply is the one
/// undoable commit and inserts the ratio for next time via the preset match.
private struct CollageCustomAspectPopover: View {
    @Bindable var model: CollageEditorModel
    @Binding var width: String
    @Binding var height: String
    let dismiss: () -> Void

    private var ratio: Double? {
        guard let w = Double(width), let h = Double(height), w > 0, h > 0 else { return nil }
        return w / h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                field($width, label: "W")
                Button {
                    swap(&width, &height)
                    previewCurrent()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle.app(AppTheme.Radius.sm).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                field($height, label: "H")
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(CollageRecipe.customShortcuts, id: \.label) { shortcut in
                    Button(shortcut.label) {
                        apply(shortcut.ratio ?? model.recipe.aspectRatio, keepFields: shortcut.ratio == nil)
                    }
                    .buttonStyle(CollageAspectChipStyle(isSelected: false))
                }
            }

            Button {
                if let ratio { model.applyCustomAspect(ratio: ratio) }
                dismiss()
            } label: {
                Text("Apply")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Size.pillHeightLight)
                    .background(EditorTheme.accent, in: RoundedRectangle.app(AppTheme.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(ratio == nil)
            .opacity(ratio == nil ? 0.4 : 1)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 240)
        .background(EditorTheme.panelSolid)
        .onChange(of: width) { _, _ in previewCurrent() }
        .onChange(of: height) { _, _ in previewCurrent() }
    }

    private func field(_ text: Binding<String>, label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(label)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.dimText)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle.app(AppTheme.Radius.sm).fill(Color.white.opacity(0.08)))
    }

    private func previewCurrent() {
        if let ratio { model.previewAspect(ratio: ratio) }
    }

    private func apply(_ ratio: Double, keepFields: Bool) {
        if !keepFields {
            // Reflect the shortcut back into the fields so W:H reads true.
            width = trimmed(ratio >= 1 ? ratio : 1)
            height = trimmed(ratio >= 1 ? 1 : 1 / ratio)
        }
        model.previewAspect(ratio: ratio)
    }

    private func trimmed(_ value: Double) -> String {
        String(format: value == value.rounded() ? "%.0f" : "%.2f", value)
    }
}

/// A wireframe of the template's cells — drawn straight from the same
/// `cellRects` the canvas uses, so the thumbnail is the layout.
struct CollageTemplateThumbnail: View {
    let template: CollageTemplate
    var isSelected: Bool

    private let side: CGFloat = 52
    private var inner: CGFloat { side - 10 }

    private func wireFrame(for cell: NormalizedRect) -> CGRect {
        let width: CGFloat = max(2, CGFloat(cell.width) * inner - 2)
        let height: CGFloat = max(2, CGFloat(cell.height) * inner - 2)
        let x: CGFloat = CGFloat(cell.x) * inner + 1
        let y: CGFloat = CGFloat(cell.y) * inner + 1
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(template.cells.enumerated()), id: \.offset) { _, cell in
                let frame = wireFrame(for: cell)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? EditorTheme.accent.opacity(0.75) : Color.white.opacity(0.35))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: inner, height: inner, alignment: .topLeading)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(isSelected ? EditorTheme.accent.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .strokeBorder(
                    isSelected ? EditorTheme.accent : Color.white.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .accessibilityLabel(String(localized: "Template \(template.id)"))
    }
}

// MARK: - Style

struct CollageStylePanel: View {
    @Bindable var model: CollageEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                EditorPlainSliderRow(
                    title: String(localized: "Border"),
                    value: model.recipe.borderWidth,
                    range: CollageRecipe.borderWidthRange,
                    isBipolar: false,
                    valueText: String(format: "%.1f", model.recipe.borderWidth * 100),
                    isActive: false,
                    onBeginDrag: {},
                    onDrag: { model.setBorderWidth($0) },
                    onEndDrag: {},
                    onReset: { model.setBorderWidth(0) }
                )
                EditorPlainSliderRow(
                    title: String(localized: "Gap"),
                    value: model.recipe.gutter,
                    range: CollageRecipe.gutterRange,
                    isBipolar: false,
                    valueText: String(format: "%.1f", model.recipe.gutter * 100),
                    isActive: false,
                    onBeginDrag: {},
                    onDrag: { model.setGutter($0) },
                    onEndDrag: {},
                    onReset: { model.setGutter(0.02) }
                )
                EditorPlainSliderRow(
                    title: String(localized: "Corners"),
                    value: model.recipe.cornerRadius,
                    range: CollageRecipe.cornerRadiusRange,
                    isBipolar: false,
                    valueText: String(format: "%.1f", model.recipe.cornerRadius * 100),
                    isActive: false,
                    onBeginDrag: {},
                    onDrag: { model.setCornerRadius($0) },
                    onEndDrag: {},
                    onReset: { model.setCornerRadius(0) }
                )
                EditorGroupHeader(title: String(localized: "Background"))
                backgroundRow
                if model.recipe.backgroundMode == .blurredPhoto {
                    blurControls
                }
                EditorGroupHeader(title: String(localized: "Style"))
                polaroidToggle
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: Background

    private var backgroundRow: some View {
        HStack(spacing: 8) {
            colorSwatch(.white, label: String(localized: "White"))
            colorSwatch(.black, label: String(localized: "Black"))
            colorSwatch(OverlayColor(red: 0.5, green: 0.5, blue: 0.5), label: String(localized: "Grey"))
            customColorSwatch
            blurPhotoSwatch
            Spacer(minLength: 0)
        }
    }

    private func colorSwatch(_ color: OverlayColor, label: String) -> some View {
        let isSelected = model.recipe.backgroundMode == .color && model.recipe.background == color
        return Button {
            model.setBackground(color)
        } label: {
            RoundedRectangle.app(AppTheme.Radius.sm)
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 34, height: 28)
                .overlay(
                    RoundedRectangle.app(AppTheme.Radius.sm)
                        .strokeBorder(isSelected ? EditorTheme.accent : Color.white.opacity(0.2),
                                      lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var customColorSwatch: some View {
        ColorPicker(
            "",
            selection: Binding(
                get: {
                    Color(red: model.recipe.background.red,
                          green: model.recipe.background.green,
                          blue: model.recipe.background.blue)
                },
                set: { newColor in
                    let resolved = UIColor(newColor)
                    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                    model.setBackground(OverlayColor(red: Double(r), green: Double(g), blue: Double(b)))
                }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
        .frame(width: 34, height: 28)
        .accessibilityLabel(String(localized: "Custom background colour"))
    }

    private var blurPhotoSwatch: some View {
        let isSelected = model.recipe.backgroundMode == .blurredPhoto
        return Button {
            model.enableBlurredBackground()
        } label: {
            RoundedRectangle.app(AppTheme.Radius.sm)
                .fill(Color.white.opacity(0.08))
                .frame(width: 34, height: 28)
                .overlay(Image(systemName: "camera.filters").font(.system(size: 13)).foregroundStyle(.white))
                .overlay(
                    RoundedRectangle.app(AppTheme.Radius.sm)
                        .strokeBorder(isSelected ? EditorTheme.accent : Color.white.opacity(0.2),
                                      lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Blurred photo background"))
    }

    private var blurControls: some View {
        VStack(spacing: 8) {
            EditorPlainSliderRow(
                title: String(localized: "Blur"),
                value: model.recipe.backgroundBlur,
                range: CollageRecipe.backgroundBlurRange,
                isBipolar: false,
                valueText: String(format: "%.0f", model.recipe.backgroundBlur * 100),
                isActive: false,
                onBeginDrag: {},
                onDrag: { model.setBackgroundBlur($0) },
                onEndDrag: {},
                onReset: { model.setBackgroundBlur(0.5) }
            )
            EditorPlainSliderRow(
                title: String(localized: "Darken"),
                value: model.recipe.backgroundDarken,
                range: CollageRecipe.backgroundDarkenRange,
                isBipolar: false,
                valueText: String(format: "%.0f", model.recipe.backgroundDarken * 100),
                isActive: false,
                onBeginDrag: {},
                onDrag: { model.setBackgroundDarken($0) },
                onEndDrag: {},
                onReset: { model.setBackgroundDarken(0.38) }
            )
        }
    }

    // MARK: Polaroid

    private var polaroidToggle: some View {
        Button {
            model.setPolaroid(!model.recipe.isPolaroid)
        } label: {
            HStack {
                Text("Polaroid")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: model.recipe.isPolaroid ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(model.recipe.isPolaroid ? EditorTheme.accent : EditorTheme.dimText)
            }
            .padding(.horizontal, 8)
            .frame(height: EditorLayoutMetrics.editorRowHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Polaroid style"))
        .accessibilityAddTraits(model.recipe.isPolaroid ? .isSelected : [])
    }
}

// MARK: - Text

struct CollageTextPanel: View {
    @Bindable var model: CollageEditorModel
    let onAddText: () -> Void
    let onEditText: (PhotoOverlay) -> Void
    let onPickFont: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Collage title — free text bands in the frame (§11).
                EditorGroupHeader(title: String(localized: "Title"), isFirst: true)

                Button(action: onAddText) {
                    Label(String(localized: "Add Title"), systemImage: "plus")
                        .font(EditorTheme.pillLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))

                ForEach(model.recipe.overlays) { overlay in
                    overlayRow(overlay)
                }

                if let overlay = model.selectedOverlay {
                    selectedOverlayControls(overlay)
                }

                // Per-photo captions — only meaningful on Polaroid plates (§11).
                if model.recipe.isPolaroid {
                    EditorGroupHeader(title: String(localized: "Captions"))
                    captionsSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    /// One editable caption per filled slot. Bound straight to the recipe so
    /// typing is live; captions are typed, never auto-filled from EXIF.
    private var captionsSection: some View {
        ForEach(model.recipe.cells.indices, id: \.self) { index in
            if !model.recipe.cells[index].isEmpty {
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(EditorTheme.rowValue)
                        .foregroundStyle(EditorTheme.dimText)
                        .frame(width: 18)
                    TextField(
                        String(localized: "Add caption"),
                        text: Binding(
                            get: { model.recipe.cells[index].caption },
                            set: { model.recipe.cells[index].caption = $0 }
                        )
                    )
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: EditorLayoutMetrics.editorRowHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(EditorTheme.maskRow))
            }
        }
    }

    private func overlayRow(_ overlay: PhotoOverlay) -> some View {
        let isSelected = model.selectedOverlayID == overlay.id
        return Button {
            model.selectedOverlayID = isSelected ? nil : overlay.id
            if isSelected == false { model.selectedCellIndex = nil }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 12))
                Text(overlay.text.isEmpty ? String(localized: "Text") : overlay.text)
                    .font(EditorTheme.rowLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Button {
                        onEditText(overlay)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.deleteSelectedOverlay()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: EditorLayoutMetrics.editorRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? EditorTheme.activeRow : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedOverlayControls(_ overlay: PhotoOverlay) -> some View {
        EditorPlainSliderRow(
            title: String(localized: "Size"),
            value: overlay.size,
            range: 0.02...0.3,
            isBipolar: false,
            valueText: String(format: "%.0f", overlay.size * 1000),
            isActive: false,
            onBeginDrag: {},
            onDrag: { newValue in
                model.updateSelectedOverlay { $0.size = newValue }
            },
            onEndDrag: {},
            onReset: {
                model.updateSelectedOverlay { $0.size = 0.06 }
            }
        )
        EditorPlainSliderRow(
            title: String(localized: "Opacity"),
            value: overlay.opacity,
            range: 0.05...1,
            isBipolar: false,
            valueText: String(format: "%.0f", overlay.opacity * 100),
            isActive: false,
            onBeginDrag: {},
            onDrag: { newValue in
                model.updateSelectedOverlay { $0.opacity = newValue }
            },
            onEndDrag: {},
            onReset: {
                model.updateSelectedOverlay { $0.opacity = 1 }
            }
        )
        HStack(spacing: 8) {
            Button {
                onPickFont()
            } label: {
                Label(String(localized: "Font"), systemImage: "textformat.alt")
                    .font(EditorTheme.pillLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: false))

            ColorPicker(
                String(localized: "Color"),
                selection: Binding(
                    get: {
                        Color(
                            red: overlay.fill.red,
                            green: overlay.fill.green,
                            blue: overlay.fill.blue
                        )
                    },
                    set: { newColor in
                        let resolved = UIColor(newColor)
                        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
                        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        let fill = OverlayColor(red: Double(red), green: Double(green), blue: Double(blue))
                        model.lastFill = fill
                        model.updateSelectedOverlay { $0.fill = fill }
                    }
                ),
                supportsOpacity: false
            )
            .font(EditorTheme.rowLabel)
            .foregroundStyle(EditorTheme.secondaryText)
        }
        .padding(.top, 2)
    }
}
