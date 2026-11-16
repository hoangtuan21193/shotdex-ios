import AppKit
import ShotDexKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Over the photo

/// Markup on the canvas (board `MAC_EditMarkup`, FS-18.03 §1f): the layers are
/// baked into the frame by the renderer; this draws the picked layer's box —
/// corner handles to size it, a knob above to turn it (with the angle) — and
/// takes the clicks: a layer picks it, a drag moves it, empty photo lets go.
struct MacEditorMarkupOverlay: View {
    @Bindable var model: MacEditorModel
    let imageRect: CGRect

    private enum Grab: Equatable {
        case move(UUID, start: NormalizedPoint)
        case resize(UUID, start: Double, from: CGFloat)
        case rotate(UUID)
        case empty
    }

    @State private var grab: Grab?
    /// The photo takes the keys once a layer is clicked on it: Delete removes that layer.
    @FocusState private var hasKeys: Bool

    private var shortEdge: CGFloat { min(imageRect.width, imageRect.height) }

    private func view(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + CGFloat(point.x) * imageRect.width, y: imageRect.minY + CGFloat(point.y) * imageRect.height)
    }

    /// The layer's box in view points, before its turn.
    private func box(_ overlay: PhotoOverlay) -> CGSize {
        switch overlay.kind {
        case .text:
            let extent = CGRect(origin: .zero, size: imageRect.size)
            return TextOverlayLayout.textContentSize(for: overlay, resolvedText: overlay.text, extent: extent, shortEdge: shortEdge)
        case .shape:
            return ShapeOverlayLayout.contentSize(for: overlay, shortEdge: shortEdge)
        case .magnifier:
            let side = CGFloat(overlay.size) * shortEdge
            return CGSize(width: side, height: side)
        case .image:
            let width = CGFloat(overlay.size) * shortEdge
            return CGSize(width: width, height: width / MacMarkupWords.imageAspect(overlay.imageID))
        case .drawing:
            return imageRect.size
        }
    }

    /// Whether `point` falls in the layer's turned box.
    private func contains(_ overlay: PhotoOverlay, _ point: CGPoint) -> Bool {
        let center = view(overlay.center), size = box(overlay)
        let angle = -overlay.rotationDegrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        let x = dx * cos(angle) - dy * sin(angle), y = dx * sin(angle) + dy * cos(angle)
        return abs(x) <= max(12, size.width / 2 + 4) && abs(y) <= max(12, size.height / 2 + 4)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: imageRect.width, height: imageRect.height)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacEditorCropOverlay.space))
                    .onChanged(changed)
                    .onEnded { _ in
                        if let held = grab, held != .empty { model.endChange() }
                        grab = nil
                    })
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Photo, layers", comment: "Mac editor markup canvas, VoiceOver"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("editor.markup.canvas")
                .focusable()
                .focused($hasKeys)
                .focusEffectDisabled()
                .onDeleteCommand { if let id = model.selectedOverlayId { model.deleteOverlay(id) } }
                .onChange(of: model.givesCanvasKeys) { hasKeys = true }
                .position(x: imageRect.midX, y: imageRect.midY)
            if let overlay = model.selectedOverlay, overlay.kind != .drawing {
                selection(overlay)
                    // A hidden layer, picked: its place shown dashed, nothing to drag.
                    .opacity(overlay.isVisible ? 1 : 0.5)
                    .allowsHitTesting(overlay.isVisible)
            }
        }
    }

    private func selection(_ overlay: PhotoOverlay) -> some View {
        let size = box(overlay)
        let center = view(overlay.center)
        // Board: the box is the layer's own, handles centred on its corners.
        let width = max(16, size.width), height = max(16, size.height)
        return ZStack {
            Rectangle().stroke(MacTheme.Editor.overlayHalo, lineWidth: 2.5)
                .frame(width: width, height: height)
            Rectangle().stroke(Color.white, lineWidth: 1.5)
                .frame(width: width, height: height)
            // The turn knob, centred on a 30pt stalk above the box, the angle beside it.
            VStack(spacing: 0) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(MacTheme.Editor.knobFill, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .overlay(alignment: .leading) {
                        Text(MacMarkupWords.degrees(overlay.rotationDegrees))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(MacTheme.Editor.readoutShade, in: Capsule())
                            .fixedSize()
                            .offset(x: 26 + 7)
                            .allowsHitTesting(false)
                    }
                    .gesture(rotateGesture(overlay, center: center))
                    .onTapGesture(count: 2) { model.updateOverlay(overlay.id) { $0.rotationDegrees = 0 } }
                    .help(String(localized: "Drag to turn · double-click for level", comment: "Mac editor markup: the turn knob tooltip"))
                    .accessibilityLabel(String(localized: "Rotate", comment: "Mac editor markup: the turn knob"))
                    .accessibilityIdentifier("editor.markup.rotate")
                Rectangle().fill(Color.white).frame(width: 1.5, height: 30)
            }
            .offset(y: -height / 2 - 28)
            ForEach(0..<4, id: \.self) { corner in
                let x = corner % 2 == 0 ? -width / 2 : width / 2
                let y = corner < 2 ? -height / 2 : height / 2
                Circle().fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .highPriorityGesture(resizeGesture(overlay, center: center))
                    .pointerStyle(.frameResize(position: corner == 0 ? .topLeading : corner == 1 ? .topTrailing : corner == 2 ? .bottomLeading : .bottomTrailing))
                    .offset(x: x, y: y)
                    .accessibilityLabel(String(localized: "Resize", comment: "Mac editor markup: a corner handle"))
                    .accessibilityIdentifier("editor.markup.handle")
            }
        }
        .rotationEffect(.degrees(overlay.rotationDegrees))
        .position(center)
    }

    // MARK: Gestures

    private func changed(_ value: DragGesture.Value) {
        if grab == nil {
            guard imageRect.contains(value.startLocation) else { grab = Grab.empty; return }
            // The picked layer first, then the topmost layer under the pointer.
            let ordered = (model.selectedOverlay.map { [$0] } ?? []) + model.recipe.overlays.reversed()
            if let hit = ordered.first(where: { $0.isVisible && $0.kind != .drawing && contains($0, value.startLocation) }) {
                model.selectedOverlayId = hit.id
                hasKeys = true
                model.beginChange()
                grab = .move(hit.id, start: hit.center)
            } else {
                // Empty photo: nothing picked.
                model.selectedOverlayId = nil
                grab = Grab.empty
            }
        }
        guard case .move(let id, let start) = grab else { return }
        let dx = Double(value.translation.width / max(1, imageRect.width))
        let dy = Double(value.translation.height / max(1, imageRect.height))
        model.updateOverlay(id, inOneStep: false) {
            $0.center = NormalizedPoint(x: min(1, max(0, start.x + dx)), y: min(1, max(0, start.y + dy)))
        }
    }

    private func resizeGesture(_ overlay: PhotoOverlay, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(MacEditorCropOverlay.space))
            .onChanged { value in
                if grab == nil {
                    model.beginChange()
                    // From the box's own corner, not where in the 22pt handle the press landed.
                    let size = box(overlay)
                    grab = .resize(overlay.id, start: overlay.size, from: max(1, hypot(size.width, size.height) / 2))
                }
                guard case .resize(let id, let start, let from) = grab else { return }
                // The size follows the corner's distance from the centre.
                let now = hypot(value.location.x - center.x, value.location.y - center.y)
                let size = MacMarkupWords.sizeRange(overlay.kind).clamped(start * Double(now / from))
                model.updateOverlay(id, inOneStep: false) { $0.size = size }
            }
            .onEnded { _ in model.endChange(); grab = nil }
    }

    private func rotateGesture(_ overlay: PhotoOverlay, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(MacEditorCropOverlay.space))
            .onChanged { value in
                if grab == nil { model.beginChange(); grab = .rotate(overlay.id) }
                guard case .rotate(let id) = grab else { return }
                // The knob points away from the centre: straight up is 0°, clockwise positive.
                var degrees = atan2(value.location.x - center.x, center.y - value.location.y) * 180 / .pi
                // Level, square and the diagonals catch the knob within 2°.
                let nearest = (degrees / 45).rounded() * 45
                if abs(degrees - nearest) < 2 { degrees = nearest }
                let rounded = (Double(degrees) * 10).rounded() / 10
                model.updateOverlay(id, inOneStep: false) { $0.rotationDegrees = rounded }
            }
            .onEnded { _ in model.endChange(); grab = nil }
    }
}

// MARK: - Inspector

/// Layers (the list, +), Add Layer (one button a kind), and the picked layer's
/// settings: text, font, size, colour, opacity, shadow; shape colour, fill,
/// line; magnifier zoom.
struct MacEditorMarkupSections: View {
    @Bindable var model: MacEditorModel
    @State private var open: Set<String> = ["layers", "add", "layer"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacEditorSectionHeader(id: "layers", title: String(localized: "Layers", comment: "Mac editor markup: a group"), open: $open) {
                Menu {
                    addItems
                } label: {
                    Label(String(localized: "Add Layer", comment: "Mac editor markup: the + menu"), systemImage: "plus").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Add Layer", comment: "Mac editor markup: the + menu"))
                .accessibilityIdentifier("editor.markup.add")
            }
            if open.contains("layers") { layerList.padding(.bottom, 10) }
            Divider()
            if let overlay = model.selectedOverlay {
                MacEditorSectionHeader(id: "layer", title: model.overlayTitle(overlay), open: $open) {
                    HStack(spacing: 2) {
                        Button { model.deleteOverlay(overlay.id) } label: {
                            Image(systemName: "trash").font(.system(size: 11)).frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help(String(localized: "Delete Layer", comment: "Mac editor markup"))
                            .accessibilityLabel(String(localized: "Delete Layer", comment: "Mac editor markup"))
                            .accessibilityIdentifier("editor.markup.delete")
                        Button { reset(overlay) } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11)).frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help(String(localized: "Reset Style", comment: "Mac editor markup: back to the kind's look; words, place, size and turn stay"))
                            .accessibilityLabel(String(localized: "Reset Style", comment: "Mac editor markup"))
                            .accessibilityIdentifier("editor.markup.reset")
                    }
                }
                if open.contains("layer") { MacMarkupLayerSettings(model: model, overlay: overlay).padding(.bottom, 10) }
                Divider()
            }
            MacEditorSectionHeader(id: "add", title: String(localized: "Add Layer", comment: "Mac editor markup: a group"), open: $open) { EmptyView() }
            if open.contains("add") {
                VStack(alignment: .leading, spacing: 6) {
                    addGrid
                    Text("Signature, Pen and Marker come in a later version.", comment: "Mac editor markup: why three buttons are dimmed")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16)
                    if let note = model.markupNote {
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 10)
            }
            Divider()
        }
    }

    /// Back to a fresh layer of the same kind; the words, place, turn and picture stay.
    private func reset(_ overlay: PhotoOverlay) {
        model.updateOverlay(overlay.id) { layer in
            var fresh = layer.kind == .shape ? PhotoOverlay.shape(layer.shapeStyle) : PhotoOverlay(kind: layer.kind)
            fresh.id = layer.id
            fresh.text = layer.text
            fresh.center = layer.center
            fresh.rotationDegrees = layer.rotationDegrees
            fresh.size = layer.size
            fresh.imageID = layer.imageID
            fresh.imageAssetIdentifier = layer.imageAssetIdentifier
            fresh.signaturePresetID = layer.signaturePresetID
            fresh.isVisible = layer.isVisible
            fresh.name = layer.name
            layer = fresh
        }
    }

    // MARK: List

    @ViewBuilder
    private var layerList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.recipe.overlays.isEmpty {
                Text("No layers yet. Add text, a shape, an arrow or a magnifier below.", comment: "Mac editor markup: empty list")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 4)
            }
            // Topmost first, as a layer list reads.
            ForEach(model.recipe.overlays.reversed()) { overlay in
                row(overlay)
            }
        }
    }

    private func row(_ overlay: PhotoOverlay) -> some View {
        let isOn = overlay.id == model.selectedOverlayId
        let title = model.overlayTitle(overlay)
        let detail = MacMarkupWords.detail(overlay, shortEdgePixels: model.healShortEdgePixels)
        return HStack(spacing: 9) {
            MacMarkupGlyph(overlay: overlay)
                .font(.system(size: 14))
                .foregroundStyle(MacTheme.Editor.label)
                .frame(width: 34, height: 23)
                .background(overlay.kind == .shape ? Color(cgColor: TextOverlayLayout.cgColor(overlay.fill)).opacity(0.35) : MacTheme.Editor.layerTile,
                            in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.updateOverlay(overlay.id) { $0.isVisible.toggle() } } label: {
                Image(systemName: overlay.isVisible ? "eye" : "eye.slash").font(.system(size: 11))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(overlay.isVisible ? String(localized: "Hide Layer", comment: "Mac editor markup") : String(localized: "Show Layer", comment: "Mac editor markup"))
            .accessibilityLabel(overlay.isVisible ? String(localized: "Hide Layer", comment: "Mac editor markup") : String(localized: "Show Layer", comment: "Mac editor markup"))
            .accessibilityIdentifier("editor.markup.visible")
        }
        .padding(.leading, 8).padding(.trailing, 6)
        .frame(height: 36)
        .background(isOn ? MacTheme.Editor.rowSelected : Color.clear, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedOverlayId = overlay.id
            model.givesCanvasKeys += 1
        }
        .padding(.horizontal, 8)
        .contextMenu {
            let isTop = overlay.id == model.recipe.overlays.last?.id, isBottom = overlay.id == model.recipe.overlays.first?.id
            Button(String(localized: "Bring to Front", comment: "Mac editor markup menu")) {
                model.apply { recipe in
                    guard let index = recipe.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
                    recipe.overlays.append(recipe.overlays.remove(at: index))
                }
            }
            .disabled(isTop)
            Button(String(localized: "Send to Back", comment: "Mac editor markup menu")) {
                model.apply { recipe in
                    guard let index = recipe.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
                    recipe.overlays.insert(recipe.overlays.remove(at: index), at: 0)
                }
            }
            .disabled(isBottom)
            Divider()
            Button(String(localized: "Delete Layer", comment: "Mac editor markup menu"), role: .destructive) { model.deleteOverlay(overlay.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.markup.row")
    }

    // MARK: Adding

    /// The board's eleven buttons, in its order; Signature, Pen and Highlighter
    /// need the drawing canvas (a later row).
    private enum AddKind: String, CaseIterable, Identifiable {
        case text, image, signature, pen, highlighter, rectangle, oval, speechBubble, arrow, line, magnifier
        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: String(localized: "Text", comment: "Mac editor markup: add a layer")
            case .image: String(localized: "Image…", comment: "Mac editor markup: add a picture from a file")
            case .signature: String(localized: "Signature", comment: "Mac editor markup: add a layer")
            case .pen: String(localized: "Pen", comment: "Mac editor markup: add a layer")
            case .highlighter: String(localized: "Marker", comment: "Mac editor markup: add a layer (a highlighter)")
            case .rectangle: OverlayShapeStyle.rectangle.displayName
            case .oval: OverlayShapeStyle.oval.displayName
            case .speechBubble: OverlayShapeStyle.speechBubble.displayName
            case .arrow: OverlayShapeStyle.arrow.displayName
            case .line: OverlayShapeStyle.line.displayName
            case .magnifier: String(localized: "Magnifier", comment: "Mac editor markup: add a layer")
            }
        }

        var symbol: String {
            switch self {
            case .text: "textformat"
            case .image: "photo"
            case .signature: "signature"
            case .pen: "pencil"
            case .highlighter: "highlighter"
            case .rectangle: "rectangle"
            case .oval: "oval"
            case .speechBubble: "bubble.left"
            case .arrow: "arrow.up.right"
            case .line: "line.diagonal"
            case .magnifier: "plus.magnifyingglass"
            }
        }

        var isAvailable: Bool { self != .signature && self != .pen && self != .highlighter }
    }

    private func add(_ kind: AddKind) {
        switch kind {
        case .text: model.addOverlay(.text())
        case .image: pickImage()
        case .rectangle: model.addOverlay(.shape(.rectangle))
        case .oval: model.addOverlay(.shape(.oval))
        case .speechBubble: model.addOverlay(.shape(.speechBubble))
        case .arrow:
            var arrow = PhotoOverlay.shape(.arrow)
            arrow.fill = MacMarkupWords.palette[2].color
            model.addOverlay(arrow)
        case .line: model.addOverlay(.shape(.line))
        case .magnifier: model.addOverlay(.magnifier())
        case .signature, .pen, .highlighter: break
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a picture to lay over the photo, like a logo", comment: "Mac editor markup: image layer open panel")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.addImageOverlay(from: url) }
        }
    }

    @ViewBuilder
    private var addItems: some View {
        ForEach(AddKind.allCases.filter(\.isAvailable)) { kind in
            Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
        }
    }

    private var addGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(AddKind.allCases) { kind in
                Button { add(kind) } label: {
                    Group {
                        if kind == .text { MacMarkupTextGlyph() } else { Image(systemName: kind.symbol) }
                    }
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(MacTheme.Editor.segmentTrack, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!kind.isAvailable)
                .opacity(kind.isAvailable ? 1 : 0.4)
                .help(kind.isAvailable ? kind.title
                      : String(localized: "\(kind.title) comes in a later version", comment: "Mac editor markup: a layer kind not built yet"))
                .accessibilityLabel(kind.title)
                .accessibilityIdentifier("editor.markup.add.\(kind.rawValue)")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }
}

/// The board's serif "T" for a text layer.
private struct MacMarkupTextGlyph: View {
    var body: some View { Text("T").font(.system(size: 15, weight: .regular, design: .serif)) }
}

/// A layer's mark: the serif T for text, the shape's or kind's symbol otherwise.
private struct MacMarkupGlyph: View {
    let overlay: PhotoOverlay
    var body: some View {
        if overlay.kind == .text { MacMarkupTextGlyph() } else { Image(systemName: MacMarkupWords.symbol(overlay)) }
    }
}

/// The picked layer's settings.
private struct MacMarkupLayerSettings: View {
    @Bindable var model: MacEditorModel
    let overlay: PhotoOverlay

    private var short: Double { model.healShortEdgePixels }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if overlay.kind == .text { text }
            if overlay.kind == .text || overlay.kind == .shape { colors }
            if overlay.kind == .shape {
                if overlay.shapeStyle.supportsFill {
                    Toggle(String(localized: "Filled", comment: "Mac editor markup: a shape filled, not outlined"),
                           isOn: Binding(get: { overlay.isFilled }, set: { on in model.updateOverlay(overlay.id) { $0.isFilled = on } }))
                        .toggleStyle(.checkbox)
                        .tint(MacTheme.Editor.accent)
                        .font(.system(size: 13))
                        .padding(.leading, 16).padding(.trailing, 12)
                        .accessibilityIdentifier("editor.markup.filled")
                }
                row(String(localized: "Line", comment: "Mac editor markup: a shape's stroke width"), overlay.strokeWidth * short, 1...(0.05 * short),
                    format: .pixels, reset: 0.006 * short, "line") { $0.strokeWidth = $1 / short }
            }
            if overlay.kind == .magnifier {
                row(String(localized: "Zoom", comment: "Mac editor markup: magnifier power"), overlay.magnification * 100, 120...600,
                    format: .plain, reset: 200, "zoom") { $0.magnification = $1 / 100 }
            }
            if overlay.kind != .text {
                row(String(localized: "Size", comment: "Mac editor markup"), overlay.size * short,
                    (MacMarkupWords.sizeRange(overlay.kind).lowerBound * short)...(MacMarkupWords.sizeRange(overlay.kind).upperBound * short),
                    format: .pixels, reset: PhotoOverlay(kind: overlay.kind).size * short, "size") { $0.size = $1 / short }
            }
            MacEditorValueRow(title: String(localized: "Turn", comment: "Mac editor markup: the layer's angle"), value: overlay.rotationDegrees,
                              range: -180...180, isBipolar: true, format: .degrees, resetValue: 0, id: "editor.markup.turn", model: model,
                              change: { value, inOneStep in model.updateOverlay(overlay.id, inOneStep: inOneStep) { $0.rotationDegrees = value } })
            row(String(localized: "Opacity", comment: "Mac editor markup"), overlay.opacity * 100, 0...100, format: .plain, reset: 100, "opacity") {
                $0.opacity = $1 / 100
            }
            if overlay.kind == .text {
                row(String(localized: "Shadow", comment: "Mac editor markup: a soft drop shadow"), overlay.shadowOpacity * 100, 0...100,
                    format: .plain, reset: 0, "shadow") { layer, value in
                    layer.shadowOpacity = value / 100
                    // One slider: the shadow's strength; its blur and drop follow the size.
                    layer.shadowRadius = value > 0 ? 0.08 : 0
                    layer.shadowOffsetY = value > 0 ? 0.04 : 0
                }
            }
        }
    }

    // MARK: Text

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacMarkupTextField(text: overlay.text, focusToken: model.focusesLayerWords) { [id = overlay.id] words in
                model.updateOverlay(id) { $0.text = words }
            }
            // One field a layer: words typed for one never land on the next.
            .id(overlay.id)
                .padding(.leading, 16).padding(.trailing, 12)
            HStack(spacing: 8) {
                Picker(String(localized: "Font", comment: "Mac editor markup"), selection: Binding(
                    get: { overlay.fontFamilyName.isEmpty ? MacMarkupWords.systemFamily : overlay.fontFamilyName },
                    set: { family in
                        model.updateOverlay(overlay.id) { layer in
                            let weight = MacMarkupWords.weight(of: layer)
                            layer.fontFamilyName = family == MacMarkupWords.systemFamily ? "" : family
                            MacMarkupWords.setWeight(weight, of: &layer)
                        }
                    })) {
                    ForEach(MacMarkupWords.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("editor.markup.font")
                Picker(String(localized: "Weight", comment: "Mac editor markup"), selection: Binding(
                    get: { MacMarkupWords.weight(of: overlay) },
                    set: { weight in
                        model.updateOverlay(overlay.id) { layer in
                            MacMarkupWords.setWeight(weight, of: &layer)
                        }
                    })) {
                    ForEach(MacMarkupWords.weights(in: overlay.fontFamilyName), id: \.value) { Text($0.name).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: 104)
                .accessibilityIdentifier("editor.markup.weight")
            }
            .padding(.leading, 16).padding(.trailing, 12)
            HStack(spacing: 6) {
                // Board: one capsule of 32×28 cells.
                HStack(spacing: 0) {
                // B is the face's weight: Regular ↔ Bold (a separate flag would do nothing on a bold face).
                let canBold = MacMarkupWords.weights(in: overlay.fontFamilyName).contains { $0.value >= 0.4 }
                toggle("bold", "B", MacMarkupWords.weight(of: overlay) >= 0.4, String(localized: "Bold", comment: "Mac editor markup")) { layer in
                    MacMarkupWords.setWeight(MacMarkupWords.weight(of: layer) >= 0.4 ? 0 : 0.4, of: &layer)
                }
                .disabled(!canBold)
                .opacity(canBold ? 1 : 0.4)
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 28)
                toggle("italic", "I", overlay.isItalic, String(localized: "Italic", comment: "Mac editor markup")) { $0.isItalic.toggle() }
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 28)
                Button {
                    model.updateOverlay(overlay.id) { layer in
                        let all = OverlayTextAlignment.allCases
                        layer.alignment = all[((all.firstIndex(of: layer.alignment) ?? 0) + 1) % all.count]
                    }
                } label: {
                    Image(systemName: overlay.alignment.systemImage).font(.system(size: 12))
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Alignment", comment: "Mac editor markup"))
                .accessibilityLabel(String(localized: "Alignment", comment: "Mac editor markup"))
                .accessibilityIdentifier("editor.markup.align")
                }
                .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                Spacer()
                MacEditorNumberField(text: "\(Int((overlay.size * short).rounded())) px") { typed in
                    guard let value = MacEditorValueRow.parse(typed), value > 0 else { return }
                    model.updateOverlay(overlay.id) { $0.size = MacMarkupWords.sizeRange(.text).clamped(value / short) }
                }
                .frame(width: 64)
                .accessibilityLabel(String(localized: "Text size", comment: "Mac editor markup"))
                .accessibilityIdentifier("editor.markup.textSize")
                Stepper("", onIncrement: { step(1.1) }, onDecrement: { step(1 / 1.1) })
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "Text size", comment: "Mac editor markup"))
            }
            .padding(.leading, 16).padding(.trailing, 12)
        }
    }

    private func step(_ factor: Double) {
        model.updateOverlay(overlay.id) { $0.size = MacMarkupWords.sizeRange(.text).clamped($0.size * factor) }
    }

    private func toggle(_ id: String, _ glyph: String, _ isOn: Bool, _ label: String,
                        _ change: @escaping (inout PhotoOverlay) -> Void) -> some View {
        Button { model.updateOverlay(overlay.id, change) } label: {
            Text(glyph)
                .font(.system(size: 12, weight: id == "bold" ? .bold : .regular))
                .italic(id == "italic")
                .frame(width: 32, height: 28)
                .background(isOn ? MacTheme.Editor.segmentOn : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("editor.markup.\(id)")
    }

    // MARK: Colour

    private var colors: some View {
        HStack(spacing: 8) {
            Text("Color", comment: "Mac editor markup: a layer's colour").font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: { Color(cgColor: TextOverlayLayout.cgColor(overlay.fill)) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    model.updateOverlay(overlay.id) {
                        $0.fill = OverlayColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
                    }
                }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier("editor.markup.colorWell")
            Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1, height: 16)
            ForEach(MacMarkupWords.palette, id: \.name) { swatch in
                let isOn = swatch.color == overlay.fill
                Button { model.updateOverlay(overlay.id) { $0.fill = swatch.color } } label: {
                    // Board: 18pt on a 26pt pitch; the chosen one ringed outside its own size.
                    Circle().fill(Color(cgColor: TextOverlayLayout.cgColor(swatch.color)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2)))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(isOn ? Color.white : Color.clear, lineWidth: 1.5).padding(-3.5))
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("editor.markup.swatch.\(swatch.name)")
            }
            Spacer()
        }
        .padding(.leading, 16).padding(.trailing, 12)
    }

    private func row(_ title: String, _ value: Double, _ range: ClosedRange<Double>, format: MacEditorValueRow.Format, reset: Double,
                     _ key: String, _ set: @escaping (inout PhotoOverlay, Double) -> Void) -> some View {
        MacEditorValueRow(title: title, value: value, range: range, isBipolar: false, format: format, resetValue: reset,
                          id: "editor.markup.\(key)", model: model, change: { value, inOneStep in
            model.updateOverlay(overlay.id, inOneStep: inOneStep) { set(&$0, value) }
        })
    }
}

/// The words of a text layer: saved on Return or when the field is left, like the number fields.
private struct MacMarkupTextField: View {
    let text: String
    /// Bumped when a text layer is added: the field takes the keys, words selected.
    let focusToken: Int
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(String(localized: "Text", comment: "Mac editor markup: the words field"), text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(MacTheme.Editor.field, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius).strokeBorder(MacTheme.Editor.fieldStroke))
            .focused($isFocused)
            .onSubmit { commit(draft) }
            .onAppear { draft = text }
            .onChange(of: text) { _, new in if !isFocused { draft = new } }
            .onChange(of: isFocused) { _, focused in if !focused, draft != text { commit(draft) } }
            .onChange(of: focusToken) { isFocused = true }
            .onAppear { if focusToken > 0, text == String(localized: "Text", comment: "Mac editor markup: a new text layer's words") { isFocused = true } }
            // Gone before Return (another tool, another photo): what was typed is kept.
            .onDisappear { if draft != text { commit(draft) } }
            .accessibilityIdentifier("editor.markup.text")
    }
}

// MARK: - Words

enum MacMarkupWords {
    struct Swatch { let name: String; let color: OverlayColor }

    /// White, black, the board's orange and red.
    static let palette: [Swatch] = [
        Swatch(name: String(localized: "White", comment: "Mac editor markup colour"), color: .init(white: 1)),
        Swatch(name: String(localized: "Black", comment: "Mac editor markup colour"), color: .init(white: 0)),
        // The editor's accent orange and the system red (`MacTheme.Editor.accent`, `channelRed`).
        Swatch(name: String(localized: "Orange", comment: "Mac editor markup colour"), color: .init(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255)),
        Swatch(name: String(localized: "Red", comment: "Mac editor markup colour"), color: .init(red: 1, green: 69 / 255, blue: 58 / 255)),
    ]

    static let systemFamily = String(localized: "System", comment: "Mac editor markup: the system font")

    /// The families offered: the system's, then the ones photographers reach for that ship with macOS.
    static let families: [String] = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let wanted = ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Georgia", "Didot", "Baskerville",
                      "Optima", "Palatino", "Menlo", "American Typewriter", "Snell Roundhand"]
        // Not New York (the board's face): it is a hidden system face the renderer
        // cannot open by name, so the photo would quietly get another font.
        return [systemFamily] + wanted.filter(installed.contains)
    }()

    static let weights: [(name: String, value: Double)] = [
        (String(localized: "Light", comment: "Mac editor markup font weight"), -0.4),
        (String(localized: "Regular", comment: "Mac editor markup font weight"), 0),
        (String(localized: "Medium", comment: "Mac editor markup font weight"), 0.23),
        (String(localized: "Semibold", comment: "Mac editor markup font weight"), 0.3),
        (String(localized: "Bold", comment: "Mac editor markup font weight"), 0.4),
    ]

    /// The weights `family` really has (System: Regular and Bold — the renderer draws it by flag).
    static func weights(in family: String) -> [(name: String, value: Double)] {
        if family.isEmpty { return weights.filter { $0.value == 0 || $0.value == 0.4 } }
        let found = weights.filter { entry in
            let name = postScriptName(family: family, weight: entry.value)
            guard let font = NSFont(name: name, size: 12) else { return false }
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            let actual = traits?[.weight] as? Double ?? 0
            return abs(actual - entry.value) < 0.06
        }
        return found.isEmpty ? weights.filter { $0.value == 0 } : found
    }

    /// One size range a kind, shared by the corner handles, the field and the slider.
    static func sizeRange(_ kind: PhotoOverlayKind) -> ClosedRange<Double> {
        kind == .text ? 0.005...1 : 0.03...1.5
    }

    /// Picks the face of the layer's family at `weight`. The system font has no
    /// face the renderer can open by name, so there the weight rides on Bold.
    static func setWeight(_ weight: Double, of layer: inout PhotoOverlay) {
        if layer.fontFamilyName.isEmpty {
            layer.fontPostScriptName = ""
            layer.isBold = weight >= 0.4
        } else {
            layer.fontPostScriptName = postScriptName(family: layer.fontFamilyName, weight: weight)
            layer.isBold = false
        }
    }

    /// Width over height of an image layer's picture, read once from its file's header.
    @MainActor private static var aspects: [UUID: CGFloat] = [:]
    @MainActor static func imageAspect(_ id: UUID?) -> CGFloat {
        guard let id else { return 2 }
        if let known = aspects[id] { return known }
        let url = MacEditorModel.overlayImages.url(for: id)
        var aspect: CGFloat = 2
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           height > 0 {
            aspect = width / height
        }
        aspects[id] = aspect
        return aspect
    }

    /// The weight the layer's face is, read back from its PostScript name (Regular when unknown).
    static func weight(of overlay: PhotoOverlay) -> Double {
        guard !overlay.fontPostScriptName.isEmpty, let font = NSFont(name: overlay.fontPostScriptName, size: 12) else {
            return overlay.isBold ? 0.4 : 0
        }
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let value = traits?[.weight] as? Double ?? 0
        return weights.min { abs($0.value - value) < abs($1.value - value) }?.value ?? 0
    }

    /// The face of `family` nearest `weight` (empty family: the system font, by weight alone).
    static func postScriptName(family: String, weight: Double) -> String {
        if family.isEmpty {
            return NSFont.systemFont(ofSize: 12, weight: NSFont.Weight(CGFloat(weight))).fontName
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: weight]])
        // A face that will not resolve falls back to the family's plain one, never to "" (the system font).
        return NSFont(descriptor: descriptor, size: 12)?.fontName
            ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)?.fontName ?? ""
    }

    static func kindName(_ overlay: PhotoOverlay) -> String {
        overlay.kind == .shape ? overlay.shapeStyle.displayName : overlay.kind.displayName
    }

    static func symbol(_ overlay: PhotoOverlay) -> String {
        overlay.kind == .shape ? overlay.shapeStyle.systemImage : overlay.kind.systemImage
    }

    /// "Skógafoss · New York 200 px", "Orange · 3 pt".
    static func detail(_ overlay: PhotoOverlay, shortEdgePixels: Double) -> String {
        switch overlay.kind {
        case .text:
            let family = overlay.fontFamilyName.isEmpty ? systemFamily : overlay.fontFamilyName
            let words = overlay.text.split(separator: "\n").first.map(String.init) ?? ""
            return "\(words) · \(family) \(Int((overlay.size * shortEdgePixels).rounded())) px"
        case .shape:
            return "\(colorName(overlay.fill)) · \(Int((overlay.strokeWidth * shortEdgePixels).rounded())) pt"
        case .magnifier:
            return String(localized: "\((overlay.magnification * 100).rounded().formatted())% zoom", comment: "Mac editor markup: magnifier detail")
        case .image:
            return String(localized: "Picture", comment: "Mac editor markup: an image layer")
        case .drawing:
            return String(localized: "Drawing", comment: "Mac editor markup: a drawing layer")
        }
    }

    static func colorName(_ color: OverlayColor) -> String {
        palette.first { $0.color == color }?.name ?? String(localized: "Custom", comment: "Mac editor markup: a picked colour")
    }

    /// "−8°", "0°".
    static func degrees(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded < 0 ? "\u{2212}\(-rounded)°" : "\(rounded)°"
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double { Swift.min(upperBound, Swift.max(lowerBound, value)) }
}
