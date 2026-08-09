import SwiftUI

/// Panel content for the collage editor's three groups. Built from the shared
/// editor pieces (`EditorPlainSliderRow`, `EditorChipButtonStyle`,
/// `EditorGroupHeader`) so the collage reads as the same tool family as the
/// photo editor. Sheets are raised by the screen; panels only call closures.

// MARK: - Layout

struct CollageLayoutPanel: View {
    @Bindable var model: CollageEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EditorGroupHeader(title: String(localized: "Template"), isFirst: true)
                templateStrip
                EditorGroupHeader(title: String(localized: "Aspect"))
                aspectChips
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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

    private var aspectChips: some View {
        HStack(spacing: 8) {
            ForEach(CollageAspect.allCases) { aspect in
                Button(aspect.displayName) {
                    model.selectAspect(aspect)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: model.recipe.aspect == aspect))
            }
        }
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
                    title: String(localized: "Spacing"),
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
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var backgroundRow: some View {
        HStack(spacing: 8) {
            backgroundPreset(.white, label: String(localized: "White"))
            backgroundPreset(.black, label: String(localized: "Black"))
            ColorPicker(
                String(localized: "Custom"),
                selection: Binding(
                    get: {
                        Color(
                            red: model.recipe.background.red,
                            green: model.recipe.background.green,
                            blue: model.recipe.background.blue
                        )
                    },
                    set: { newColor in
                        let resolved = UIColor(newColor)
                        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
                        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        model.setBackground(OverlayColor(
                            red: Double(red),
                            green: Double(green),
                            blue: Double(blue)
                        ))
                    }
                ),
                supportsOpacity: false
            )
            .font(EditorTheme.rowLabel)
            .foregroundStyle(EditorTheme.secondaryText)
        }
    }

    private func backgroundPreset(_ color: OverlayColor, label: String) -> some View {
        Button {
            model.setBackground(color)
        } label: {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(
                        model.recipe.background == color
                            ? EditorTheme.accent
                            : Color.white.opacity(0.25),
                        lineWidth: model.recipe.background == color ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                EditorGroupHeader(title: String(localized: "Text"), isFirst: true)

                Button(action: onAddText) {
                    Label(String(localized: "Add Text"), systemImage: "plus")
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
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
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
