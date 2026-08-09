import SwiftUI

/// Masks tab, list level. One primary action — New Mask — and one row per mask
/// with its real shape and a summary of what it changes. Everything else lives a
/// level down, inside the mask.
struct EditorMaskListPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Masks")
                        .font(EditorTheme.panelTitle)
                        .foregroundStyle(.white)
                    Text("Tap a mask to adjust that area on its own")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    chrome.isNewMaskSheetPresented = true
                } label: {
                    Label("New Mask", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(EditorTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if controller.recipe.masks.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 26))
                .foregroundStyle(EditorTheme.dimText)
            Text("No masks yet")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
            Text("A mask limits Light, Color, Detail and Effects to one area.")
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(controller.recipe.masks) { mask in
                EditorMaskRow(
                    mask: mask,
                    thumbnail: controller.maskThumbnails[mask.id],
                    isSelected: controller.selectedMaskID == mask.id,
                    onOpen: { open(mask) },
                    onToggleVisibility: {
                        controller.selectMask(mask.id)
                        controller.toggleSelectedMaskVisibility()
                    },
                    onDuplicate: {
                        controller.selectMask(mask.id)
                        controller.duplicateSelectedMask()
                    },
                    onRename: {
                        controller.selectMask(mask.id)
                        rename()
                    },
                    onInvert: {
                        controller.selectMask(mask.id)
                        controller.invertSelectedMask()
                    },
                    onDelete: {
                        controller.selectMask(mask.id)
                        controller.deleteSelectedMask()
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
    }

    private func open(_ mask: PhotoMask) {
        controller.selectMask(mask.id)
        controller.editSelectedMaskAdjustments()
    }
}

struct EditorMaskRow: View {
    let mask: PhotoMask
    let thumbnail: UIImage?
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleVisibility: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onInvert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(mask.name)
                    .font(EditorTheme.maskTitle)
                    .foregroundStyle(isSelected ? EditorTheme.accent : .white)
                    .lineLimit(1)
                Text(
                    EditorAdjustmentSummary.text(for: mask.adjustments)
                        ?? "No adjustments yet"
                )
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onToggleVisibility) {
                Image(systemName: mask.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(
                        mask.isVisible ? EditorTheme.accent : EditorTheme.dimText
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mask effect")
            .accessibilityValue(mask.isVisible ? "On" : "Off")

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(
            isSelected ? EditorTheme.accent.opacity(0.13) : EditorTheme.maskRow,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(EditorTheme.accent.opacity(0.4), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: onInvert) {
                Label(
                    mask.isInverted ? "Remove Invert" : "Invert",
                    systemImage: "circle.righthalf.filled"
                )
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var thumbnailView: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 42, height: 42)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        // The frame must come before the clip: `.fill` sizes the
                        // view to the aspect-filled rect, so without it a
                        // portrait matte grew to the row's full height and sat
                        // flush against the card's edges.
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                } else {
                    Image(systemName: mask.components.first?.kind.systemImage ?? "circle.dashed")
                        .font(.system(size: 15))
                        .foregroundStyle(EditorTheme.dimText)
                }
            }
            .accessibilityHidden(true)
    }
}


/// Mask housekeeping in the panel's nav row: rename and duplicate, plus dropping
/// one shape of a multi-shape mask. Delete-the-mask lives on the action row as a
/// flat button, so it is not repeated here.
struct EditorMaskActionsMenu: View {
    @Bindable var controller: PhotoEditorController
    let rename: () -> Void
    /// Removes the whole mask and returns to the list. Turn 31 moved this off the
    /// (now gone) command row and into here.
    var deleteMask: (() -> Void)?

    var body: some View {
        Menu {
            // Undo and redo are on the action row everywhere else, but that row is
            // the shape controls while a mask is open — which left the one tool
            // where a wrong move is a stroke of paint with no way to take it back
            // short of leaving the mask.
            Button {
                controller.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!controller.canUndo)
            Button {
                controller.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!controller.canRedo)
            Divider()
            Button(action: rename) {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                controller.duplicateSelectedMask()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            // "Shape", not "Region": a mask is built out of shapes (a brush, a
            // gradient…) combined with +/−. "Region" next to "Mask" read as two
            // names for the same thing.
            if (controller.selectedMask?.components.count ?? 0) > 1 {
                Button(role: .destructive) {
                    controller.deleteSelectedComponent()
                } label: {
                    Label("Delete This Shape", systemImage: "minus.circle")
                }
            }
            if let deleteMask {
                Divider()
                Button(role: .destructive, action: deleteMask) {
                    Label("Delete Mask", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Mask actions")
    }
}

struct EditorMaskDetailPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void

    private var maskIndexLabel: String {
        guard let id = controller.selectedMaskID,
              let index = controller.recipe.masks.firstIndex(where: { $0.id == id })
        else { return "" }
        return "\(index + 1)/\(controller.recipe.masks.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationRow
            EditorAdjustmentGroupsView(
                controller: controller,
                chrome: chrome,
                groups: EditorAdjustmentCatalog.groups(
                    isRAWSource: controller.isRAWSource,
                    scope: .mask
                ),
                footer: { maskShapeSection }
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorTheme.accent.opacity(0.6))
                .frame(height: 2)
        }
    }

    /// Second level of the Masks tab: back to the list, which mask this is, its
    /// effect switch and its own menu. The action row above carries the *shape*
    /// controls instead.
    private var navigationRow: some View {
        HStack(spacing: 8) {
            Button {
                chrome.resetZoom()
                controller.closeSelectedMaskAdjustments()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Masks")
                        .font(.system(size: 15))
                }
                .foregroundStyle(EditorTheme.accent)
                .padding(.trailing, 6)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                chrome.isMaskPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    if let id = controller.selectedMaskID,
                       let thumbnail = controller.maskThumbnails[id] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    }
                    Text(controller.selectedMask?.name ?? "Mask")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(maskIndexLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // One-tap undo, because the thing most likely to need taking back in
            // here is a brush stroke and a menu is two taps too many. Redo is
            // rarer, so it stays in the `⋯` menu with this one.
            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        controller.canUndo
                            ? EditorTheme.secondaryText
                            : EditorTheme.dimText.opacity(0.5)
                    )
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canUndo)
            .accessibilityLabel("Undo")

            // The mask's *effect* on and off, and it is the eye on purpose:
            // Lightroom and every layers panel taught that instinct, and a
            // checkmark here got read as some kind of selection state. The red
            // overlay in the action row is the one with its own glyph — a red
            // dot, the literal colour it switches.
            Button {
                controller.toggleSelectedMaskVisibility()
            } label: {
                let isEnabled = controller.selectedMask?.isVisible != false
                Image(systemName: isEnabled ? "eye" : "eye.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(isEnabled ? EditorTheme.accent : EditorTheme.dimText)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mask effect")
            .accessibilityValue(
                controller.selectedMask?.isVisible == false ? "Off" : "On"
            )

            EditorMaskActionsMenu(controller: controller, rename: rename) {
                controller.deleteSelectedMask()
                chrome.resetZoom()
                controller.closeSelectedMaskAdjustments()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: EditorLayoutMetrics.maskNavigationRowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var maskShapeSection: some View {
        if let component = controller.selectedComponent {
            EditorGroupHeader(title: "Mask · Shape")

            // Add / Subtract for new strokes and shapes. Turn 31 moved it off the
            // command row into the shape section, where it is in reach while
            // painting.
            addSubtractRow

            if (controller.selectedMask?.components.count ?? 0) > 1 {
                componentPicker
            }

            switch component.kind {
            case .brush:
                brushRows(component)
            case .linearGradient:
                hint("Drag the photo to move the gradient, the dots to reshape it")
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            case .radialGradient:
                hint("Drag the photo to move, the dots to resize")
                shapeFeatherRow(component)
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            case .subject:
                hint("Tap a person or object on the photo")
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            case .sky:
                hint("Sky detected on device")
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            case .luminanceRange:
                hint("Pick the range with the Min and Max sliders")
                componentSlider("Min", keyPath: \.luminanceMinimum, range: 0...1)
                componentSlider("Max", keyPath: \.luminanceMaximum, range: 0...1)
                shapeFeatherRow(component)
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            case .colorRange:
                hint("Tap a colour on the photo")
                componentSlider("Range", keyPath: \.colorTolerance, range: 0.01...1)
                shapeFeatherRow(component)
                componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
            }
        }
    }

    /// Add / Subtract for the next stroke or shape, mirroring `maskOperation`.
    private var addSubtractRow: some View {
        HStack(spacing: 8) {
            ForEach(MaskBlendOperation.allCases) { operation in
                Button {
                    controller.maskOperation = operation
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: operation == .add ? "plus.circle" : "minus.circle"
                        )
                        Text(operation == .add ? "Add" : "Subtract")
                    }
                }
                .buttonStyle(
                    EditorChipButtonStyle(isSelected: controller.maskOperation == operation)
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private var componentPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(controller.selectedMask?.components ?? []) { component in
                    Button {
                        controller.selectComponent(component.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(
                                systemName: component.operation == .add
                                    ? "plus.circle"
                                    : "minus.circle"
                            )
                            Text(component.kind.displayName)
                        }
                    }
                    .buttonStyle(
                        EditorChipButtonStyle(
                            isSelected: component.id == controller.selectedComponentID
                        )
                    )
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .frame(height: 52)
    }

    /// Size / Feather / Flow are all rows now (28c): the whole panel is one row
    /// language, and the shape controls left the floating pod for the action bar.
    @ViewBuilder
    private func brushRows(_ component: PhotoMaskComponent) -> some View {
        brushSlider("Size", value: controller.brushSize, range: EditorLayoutMetrics.brushSizeRange, resetTo: 0.25) {
            controller.brushSize = $0
        }
        brushSlider("Feather", value: controller.brushFeather, range: 0...1, resetTo: 0.45) {
            controller.brushFeather = $0
        }
        brushSlider("Flow", value: controller.brushFlow, range: 0.05...1, resetTo: 0.8) {
            controller.brushFlow = $0
        }
        componentSlider("Opacity", keyPath: \.opacity, range: 0.01...1)
        Button("Clear Strokes") {
            controller.updateSelectedComponent { $0.brushStrokes = [] }
        }
        .buttonStyle(EditorTextButtonStyle())
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(component.brushStrokes.isEmpty)
    }

    private func componentSlider(
        _ title: String,
        keyPath: WritableKeyPath<PhotoMaskComponent, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: controller.selectedComponent?[keyPath: keyPath] ?? 0,
            range: range,
            isBipolar: false,
            valueText: percent(
                (controller.selectedComponent?[keyPath: keyPath] ?? 0)
                    / max(0.0001, range.upperBound)
            ),
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { value in
                controller.updateSelectedComponent { $0[keyPath: keyPath] = value }
            },
            onEndDrag: { controller.endContinuousChange() },
            onReset: {}
        )
    }

    /// Brush parameters (Size / Feather / Flow) live on the controller, not the
    /// recipe: no history entry and no continuous-change bracket, so their rows
    /// skip the `beginContinuousChange` plumbing the recipe-backed rows use.
    private func brushSlider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        resetTo: Double,
        write: @escaping (Double) -> Void
    ) -> some View {
        EditorPlainSliderRow(
            title: title,
            value: value,
            range: range,
            isBipolar: false,
            valueText: EditorLayoutMetrics.brushAmountText(value, in: range),
            isActive: false,
            onBeginDrag: {},
            onDrag: write,
            onEndDrag: {},
            onReset: { write(resetTo) }
        )
    }

    /// A radial / luminance / colour-range shape's own feather, as a row (it used
    /// to be a popup dialog off the floating shape controls).
    private func shapeFeatherRow(_ component: PhotoMaskComponent) -> some View {
        EditorPlainSliderRow(
            title: "Feather",
            value: component.feather,
            range: 0...1,
            isBipolar: false,
            valueText: EditorLayoutMetrics.brushAmountText(component.feather, in: 0...1),
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { value in
                controller.updateSelectedComponent { $0.feather = value }
            },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.updateSelectedComponent { $0.feather = 0 } }
        )
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .padding(.horizontal, 14)
            .frame(height: 32, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }
}

/// Sheet for creating a mask. Each kind says what it does, because `Luminance
/// Range` means nothing to someone who has not used it before.
struct EditorNewMaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PhotoMaskComponentKind) -> Void

    private let descriptions: [PhotoMaskComponentKind: String] = [
        .subject: "Isolates the subject on device",
        .sky: "Finds the sky automatically",
        .radialGradient: "Elliptical area, drag to place",
        .linearGradient: "Straight transition across the frame",
        .colorRange: "Tap a colour on the photo",
        .luminanceRange: "Follows a band of brightness",
        .brush: "Paint by hand · size, flow, feather",
    ]

    private let order: [PhotoMaskComponentKind] = [
        .subject, .sky, .brush, .radialGradient, .linearGradient, .colorRange,
        .luminanceRange,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose how to select the area. You can add and subtract several kinds inside one mask.")
                        .font(.system(size: 13))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .padding(.horizontal, 4)

                    // One flat column of same-height rows, icon on the left —
                    // the two-column tile grid wrapped its blurbs to different
                    // line counts, so every card was a different size and the
                    // sheet ate the screen.
                    VStack(spacing: 8) {
                        ForEach(order) { kind in
                            row(kind)
                        }
                    }
                }
                .padding(16)
            }
            .background(EditorTheme.panel)
            .navigationTitle("New Mask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ kind: PhotoMaskComponentKind) -> some View {
        Button {
            onSelect(kind)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(EditorTheme.accent)
                    // Fixed slot so the text column lines up across rows no
                    // matter how wide the glyph is.
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(descriptions[kind] ?? "")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            // The height is the row's, not the text's: every card identical.
            .frame(height: 54)
            .background(EditorTheme.maskRow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Quick jump between masks from the `n/m` control in the mask editor.
struct EditorMaskPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let masks: [PhotoMask]
    let selectedID: UUID?
    let thumbnails: [UUID: UIImage]
    let onSelect: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List(masks) { mask in
                Button {
                    onSelect(mask.id)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        if let image = thumbnails[mask.id] {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mask.name)
                                .foregroundStyle(.white)
                            if let summary = EditorAdjustmentSummary.text(
                                for: mask.adjustments,
                                limit: 2
                            ) {
                                Text(summary)
                                    .font(EditorTheme.maskSubtitle)
                                    .foregroundStyle(EditorTheme.secondaryText)
                            }
                        }
                        Spacer()
                        if mask.id == selectedID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(EditorTheme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Masks")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
