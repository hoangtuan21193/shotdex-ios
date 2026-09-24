import PencilKit
import SwiftUI
import ShotDexKit

/// The Markup tab on the phone panel (FS-05.01 §6): the same two states as Mask.
/// With no layer (or after `+`), "Add a layer" — three rows of chips, one tap makes
/// the layer. Otherwise the selected layer's rows, under the layer strip.
struct EditorMarkupPhonePanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let addText: () -> Void
    let addImage: () -> Void
    let startDrawing: (EditorDrawInk) -> Void
    let openSignatures: () -> Void
    let layerRows: () -> AnyView

    static func showsChooser(controller: PhotoEditorController, chrome: EditorChromeModel) -> Bool {
        controller.recipe.overlays.isEmpty || chrome.isChoosingLayerKind
    }

    var body: some View {
        Group {
            if let palette = chrome.colorPalette {
                EditorColorPalettePanel(chrome: chrome, request: palette)
            } else if Self.showsChooser(controller: controller, chrome: chrome) {
                chooser
            } else {
                layerRows()
            }
        }
        .onAppear(perform: keepALayerOpen)
        .onDisappear {
            chrome.isChoosingLayerKind = false
            chrome.colorPalette = nil
            chrome.markupColorSampler = nil
        }
        // A different layer, or none: the palette was for the old one.
        .onChange(of: controller.selectedOverlayID) { _, _ in
            chrome.colorPalette = nil
            chrome.markupColorSampler = nil
        }
        .onChange(of: controller.recipe.overlays.map(\.id)) { keepALayerOpen() }
        .onChange(of: controller.selectedOverlayID) { keepALayerOpen() }
    }

    /// With layers present one of them is always the one the rows edit — the top
    /// one after a delete or undo cleared the selection. There is no list to fall
    /// back to on the phone.
    private func keepALayerOpen() {
        guard !chrome.isChoosingLayerKind, !controller.isEditingDrawing else { return }
        if controller.selectedOverlayID == nil, let top = controller.recipe.overlays.last {
            controller.openOverlayDetail(top.id)
        } else if let id = controller.selectedOverlayID, !controller.showsOverlayDetail {
            controller.openOverlayDetail(id)
        }
    }

    // MARK: Add a layer

    private enum Choice: Hashable {
        case text, image, sign, pen, marker, magnifier
        case shape(OverlayShapeStyle)

        var title: String {
            switch self {
            case .text: "Text"
            case .image: "Image"
            case .sign: "Sign"
            case .pen: "Pen"
            case .marker: "Marker"
            case .magnifier: "Magnifier"
            case .shape(let style): style.displayName
            }
        }

        var systemImage: String {
            switch self {
            case .text: "textformat"
            case .image: "photo"
            case .sign: "signature"
            case .pen: "pencil.tip"
            case .marker: "highlighter"
            case .magnifier: "plus.magnifyingglass"
            case .shape(let style): style.systemImage
            }
        }
    }

    /// Three rows: what is typed or placed, what is drawn by hand, and the shapes.
    /// Every layer kind the old Add Layer menu offered is here.
    private static let rows: [[Choice]] = [
        [.text, .image, .sign],
        [.pen, .marker],
        OverlayShapeStyle.allCases.map(Choice.shape) + [.magnifier],
    ]

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if !controller.recipe.overlays.isEmpty {
                    Button {
                        chrome.isChoosingLayerKind = false
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to layers")
                }
                Text("Add a layer")
                    .font(.system(size: 13))
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: EditorLayoutMetrics.editorPanelRowHeight)

            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                ScrollView(.horizontal) {
                    HStack(spacing: EditorStripLayout.chipSpacing) {
                        ForEach(row, id: \.self) { choice in
                            Button {
                                choose(choice)
                            } label: {
                                EditorPanelChipLabel(title: choice.title, systemImage: choice.systemImage)
                            }
                            .buttonStyle(EditorChipButtonStyle(isSelected: false))
                            .accessibilityLabel("Add \(choice.title)")
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
            }
            Spacer(minLength: 0)
        }
    }

    private func choose(_ choice: Choice) {
        chrome.isChoosingLayerKind = false
        switch choice {
        case .text: addText()
        case .image: addImage()
        case .sign: openSignatures()
        case .pen: startDrawing(.pen)
        case .marker: startDrawing(.marker)
        case .magnifier: controller.addMagnifierOverlay()
        case .shape(let style): controller.addShapeOverlay(style)
        }
    }
}

/// The phone panel's Markup target strip: a 40×30 tile per layer (front-most
/// first, the way a layer list reads), `+`, the selected layer's name and its `⋯`.
/// The strip scrolls to the selected layer whenever it changes — including a tap
/// on the layer on the photo (FS-05.03 §4).
struct EditorLayerStrip: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let rename: () -> Void
    let replaceImage: () -> Void
    let saveSignature: () -> Void
    @State private var dropTarget: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(controller.recipe.overlays.reversed()) { overlay in
                            tile(overlay).id(overlay.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: controller.selectedOverlayID) { _, id in
                    guard let id else { return }
                    withAnimation(EditorTheme.animation) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = controller.selectedOverlayID { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(maxWidth: CGFloat(controller.recipe.overlays.count) * 48)
            .layoutPriority(1)

            Button {
                chrome.isChoosingLayerKind = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(EditorTheme.chipIdle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a layer")

            Text(controller.selectedOverlay.map(controller.displayName(of:)) ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    minWidth: EditorLayoutMetrics.editorThumbnailStripNameMinWidth,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.leading, AppTheme.Spacing.xs)

            EditorLayerActionsMenu(
                controller: controller,
                rename: rename,
                replaceImage: replaceImage,
                saveSignature: saveSignature
            )
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ overlay: PhotoOverlay) -> some View {
        let isSelected = controller.selectedOverlayID == overlay.id
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        let glyphColor: Color = overlay.kind == .text
            ? Color(red: overlay.fill.red, green: overlay.fill.green, blue: overlay.fill.blue)
            : .white
        return Button {
            chrome.isChoosingLayerKind = false
            controller.openOverlayDetail(overlay.id)
        } label: {
            shape
                .fill(EditorTheme.control)
                .frame(width: 40, height: 30)
                .overlay {
                    Image(systemName: overlay.kind == .shape ? overlay.shapeStyle.systemImage : overlay.kind.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(glyphColor)
                }
                .opacity(overlay.isVisible ? 1 : EditorTheme.rowDisabled)
                .padding(3.5)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm + 3.5, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                    }
                }
                .frame(width: 48, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Touch and hold, then drag onto another tile to restack (FS-05.01 §3).
        .draggable(overlay.id.uuidString) {
            Image(systemName: overlay.kind == .shape ? overlay.shapeStyle.systemImage : overlay.kind.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 30)
                .background(EditorTheme.control, in: shape)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            controller.moveOverlay(id: dragged, ontoOverlay: overlay.id)
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? overlay.id : (dropTarget == overlay.id ? nil : dropTarget)
        }
        .overlay {
            if dropTarget == overlay.id {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm + 3.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 47, height: 37)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(controller.displayName(of: overlay))
        .accessibilityValue(overlay.isVisible ? "" : "Hidden")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The layer's `⋯` on the phone strip: everything the old list row, its swipe and
/// the detail header did to a layer, in one menu.
struct EditorLayerActionsMenu: View {
    @Bindable var controller: PhotoEditorController
    let rename: () -> Void
    let replaceImage: () -> Void
    let saveSignature: () -> Void

    var body: some View {
        Menu {
            if let layer = controller.selectedOverlay {
                Button(action: rename) { Label("Rename", systemImage: "pencil") }
                Button {
                    controller.duplicateSelectedOverlay()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    controller.toggleSelectedOverlayVisibility()
                } label: {
                    if layer.isVisible {
                        Label("Hide", systemImage: "eye.slash")
                    } else {
                        Label("Show", systemImage: "eye")
                    }
                }
                Divider()
                Button {
                    controller.moveSelectedOverlayForward()
                } label: {
                    Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled")
                }
                .disabled(controller.recipe.overlays.last?.id == layer.id)
                Button {
                    controller.moveSelectedOverlayBackward()
                } label: {
                    Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled")
                }
                .disabled(controller.recipe.overlays.first?.id == layer.id)
                Divider()
                if layer.kind == .image {
                    Button(action: replaceImage) { Label("Replace Image", systemImage: "photo") }
                }
                if layer.kind == .drawing {
                    Button {
                        controller.clearDrawing()
                    } label: {
                        Label("Clear Strokes", systemImage: "eraser")
                    }
                    .disabled(layer.drawing == nil)
                }
                if layer.kind != .drawing {
                    Button(action: saveSignature) { Label("Save as Preset", systemImage: "signature") }
                }
                Divider()
                Button(role: .destructive) {
                    controller.deleteSelectedOverlay()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button(role: .destructive) {
                controller.removeAllOverlays()
            } label: {
                Label("Remove All Layers", systemImage: "trash.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Layer actions")
    }
}

/// Which PencilKit ink a new drawing layer starts with — every ink the system
/// tool picker offered.
enum EditorDrawInk: String, CaseIterable, Identifiable {
    case pen, marker, pencil, fountainPen, monoline, watercolor, crayon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .pencil: "Pencil"
        case .fountainPen: "Fountain"
        case .monoline: "Monoline"
        case .watercolor: "Watercolor"
        case .crayon: "Crayon"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil"
        case .fountainPen: "pencil.and.scribble"
        case .monoline: "line.diagonal"
        case .watercolor: "paintbrush"
        case .crayon: "pencil.and.outline"
        }
    }

    var pkType: PKInkingTool.InkType {
        switch self {
        case .pen: .pen
        case .marker: .marker
        case .pencil: .pencil
        case .fountainPen: .fountainPen
        case .monoline: .monoline
        case .watercolor: .watercolor
        case .crayon: .crayon
        }
    }
}

/// A drawing layer's rows on the phone panel (FS-05.01 §4): Draw · Erase · Select
/// with the Ruler, then the ink (or the eraser kind), then Size, Opacity and
/// Color. The panel sets the PencilKit tool; the system tool picker never shows.
struct EditorDrawRows: View {
    @Bindable var session: EditorDrawSession
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    @Environment(\.editorPanelScrolls) private var panelScrolls

    var body: some View {
        VStack(spacing: 0) {
            modeRow
            if session.mode == .draw {
                chipRow(EditorDrawInk.allCases, isSelected: { session.ink == $0 }) { ink in
                    EditorPanelChipLabel(title: ink.title, systemImage: ink.systemImage)
                } select: { session.ink = $0 }
            } else if session.mode == .erase {
                chipRow(EditorDrawSession.EraserKind.allCases, isSelected: { session.eraserKind == $0 }) { kind in
                    EditorPanelChipLabel(title: kind.title, systemImage: kind == .strokes ? "scribble" : "eraser")
                } select: { session.eraserKind = $0 }
            }
            if session.mode != .select {
                EditorPlainSliderRow(
                    title: "Size",
                    value: Double(session.width),
                    range: Double(session.widthRange.lowerBound)...Double(session.widthRange.upperBound),
                    isBipolar: false,
                    valueText: String(format: "%.0f", session.width),
                    isActive: false,
                    onBeginDrag: {},
                    onDrag: { session.width = CGFloat($0) },
                    onEndDrag: {},
                    onReset: { session.width = session.ink.pkType.defaultWidth }
                )
            }
            if session.mode == .draw {
                EditorPlainSliderRow(
                    title: "Opacity",
                    value: session.opacity * 100,
                    range: 5...100,
                    isBipolar: false,
                    valueText: "\(Int((session.opacity * 100).rounded()))%",
                    isActive: false,
                    detent: 100,
                    onBeginDrag: {},
                    onDrag: { session.opacity = $0 / 100 },
                    onEndDrag: {},
                    onReset: { session.opacity = 1 }
                )
                EditorOverlayColorControl(
                    chrome: chrome,
                    idPrefix: "draw.color",
                    color: session.color,
                    onBegin: {},
                    onChange: { session.color = $0 },
                    onEnd: {}
                )
            }
            Color.clear.frame(height: 16)
        }
        .editorPanelScroll(panelScrolls)
        .scrollDisabled(chrome.activePlainSliderID != nil)
    }

    private var modeRow: some View {
        HStack(spacing: EditorStripLayout.chipSpacing) {
            ForEach(EditorDrawSession.Mode.allCases) { mode in
                Button {
                    session.mode = mode
                } label: {
                    EditorPanelChipLabel(title: mode.title, systemImage: mode.systemImage)
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: session.mode == mode))
                .accessibilityAddTraits(session.mode == mode ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button {
                session.isRulerActive.toggle()
            } label: {
                EditorPanelChipLabel(title: "Ruler", systemImage: "ruler")
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: session.isRulerActive))
            .accessibilityValue(session.isRulerActive ? "On" : "Off")
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }

    private func chipRow<Item: Identifiable>(
        _ items: [Item],
        isSelected: @escaping (Item) -> Bool,
        label: @escaping (Item) -> EditorPanelChipLabel,
        select: @escaping (Item) -> Void
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: EditorStripLayout.chipSpacing) {
                ForEach(items) { item in
                    Button { select(item) } label: { label(item) }
                        .buttonStyle(EditorChipButtonStyle(isSelected: isSelected(item)))
                        .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
                }
            }
            .padding(.horizontal, EditorStripLayout.horizontalInset)
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }
}
