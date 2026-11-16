import ShotDexKit
import SwiftUI

// MARK: - Over the photo

/// Mask on the canvas (board `MAC_EditMask`, FS-18.03 §1e): the picked area
/// decides what the pointer does — a Brush paints (or erases), a gradient is
/// laid by a drag, Object / Subject / Color Range take a click. The mask
/// itself shows in red, drawn by the renderer.
struct MacEditorMaskOverlay: View {
    @Bindable var model: MacEditorModel
    let imageRect: CGRect
    @State private var hover: CGPoint?
    @State private var dragging = false
    /// The area kind the drag began on: it ends the way it began.
    @State private var dragKind: PhotoMaskComponentKind?

    private var kind: PhotoMaskComponentKind? { model.selectedComponent?.kind }

    private func view(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + CGFloat(point.x) * imageRect.width, y: imageRect.minY + CGFloat(point.y) * imageRect.height)
    }

    private func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: min(1, max(0, Double((point.x - imageRect.minX) / max(1, imageRect.width)))),
                        y: min(1, max(0, Double((point.y - imageRect.minY) / max(1, imageRect.height)))))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(in: &context) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Editor.label)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(MacTheme.Editor.glass, in: Capsule())
                    .overlay(Capsule().strokeBorder(MacTheme.Editor.glassStroke))
                    .position(x: imageRect.midX, y: imageRect.minY + 22)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("editor.mask.hint")
            }
            Color.clear
                .contentShape(Rectangle())
                .frame(width: imageRect.width, height: imageRect.height)
                .onContinuousHover(coordinateSpace: .named(MacEditorCropOverlay.space)) { phase in
                    if case .active(let point) = phase, imageRect.contains(point) { hover = point } else { hover = nil }
                }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacEditorCropOverlay.space))
                    .onChanged(changed)
                    .onEnded(ended))
                .pointerStyle(.rectSelection)
                // The brush ring is the pointer while painting; the arrow would sit on top of it.
                .pointerVisibility(kind == .brush && hover != nil ? .hidden : .automatic)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Photo, mask area", comment: "Mac editor mask canvas, VoiceOver"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("editor.mask.canvas")
                .position(x: imageRect.midX, y: imageRect.midY)
        }
    }

    /// What the pointer does now, said over the photo while nothing is drawn yet.
    private var hint: String? {
        guard let component = model.selectedComponent, !dragging else {
            return model.recipe.masks.isEmpty
                ? String(localized: "Add a mask with + in Masks", comment: "Mac editor mask: nothing to edit yet") : nil
        }
        if model.emptyAutoAreas.contains(component.id) {
            return Self.nothingFound(component.kind)
        }
        switch component.kind {
        case .brush where component.brushStrokes.isEmpty:
            return String(localized: "Paint over the area to mask it", comment: "Mac editor mask: brush hint")
        case .linearGradient, .radialGradient:
            return String(localized: "Drag on the photo to place the gradient · drag again to place it anew", comment: "Mac editor mask: gradient hint")
        case .subject, .sky, .people, .depthRange:
            return model.resolvedAutoAreas.contains(component.id)
                ? nil : String(localized: "Finding it in the photo…", comment: "Mac editor mask: automatic detection running")
        case .object where component.objectPoint == nil:
            return String(localized: "Click the object to mask", comment: "Mac editor mask: object hint")
        case .colorRange:
            return String(localized: "Click a color to mask everything like it", comment: "Mac editor mask: color range hint")
        default:
            return nil
        }
    }

    static func nothingFound(_ kind: PhotoMaskComponentKind) -> String {
        switch kind {
        case .sky: String(localized: "No sky found in this photo", comment: "Mac editor mask: detection found nothing")
        case .subject: String(localized: "No subject found in this photo", comment: "Mac editor mask: detection found nothing")
        case .people: String(localized: "No people found in this photo", comment: "Mac editor mask: detection found nothing")
        case .object: String(localized: "Nothing found there — click another spot", comment: "Mac editor mask: object found nothing")
        default: String(localized: "Nothing found for this area", comment: "Mac editor mask: detection found nothing")
        }
    }

    private func draw(in context: inout GraphicsContext) {
        guard let component = model.selectedComponent else { return }
        let white = GraphicsContext.Shading.color(.white)
        let halo = GraphicsContext.Shading.color(MacTheme.Editor.overlayHalo)
        func line(_ path: Path, width: CGFloat = 1.4, dashed: Bool = false) {
            let dash: [CGFloat] = dashed ? [5, 4] : []
            context.stroke(path, with: halo, style: StrokeStyle(lineWidth: width + 1.5, dash: dash))
            context.stroke(path, with: white, style: StrokeStyle(lineWidth: width, dash: dash))
        }
        func dot(_ point: CGPoint, _ radius: CGFloat = 5) {
            let path = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(path, with: white)
            context.stroke(path, with: halo, lineWidth: 1)
        }
        switch component.kind {
        case .linearGradient:
            // The two ends and the midline: the area runs from the full line to the dashed one.
            let start = view(component.startPoint), end = view(component.endPoint)
            let dx = end.x - start.x, dy = end.y - start.y, length = max(1, hypot(dx, dy))
            let normal = CGPoint(x: -dy / length * 2000, y: dx / length * 2000)
            for (point, dashed) in [(start, false), (end, true), (CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), true)] {
                var across = Path()
                across.move(to: CGPoint(x: point.x - normal.x, y: point.y - normal.y))
                across.addLine(to: CGPoint(x: point.x + normal.x, y: point.y + normal.y))
                line(across, width: 1, dashed: dashed)
            }
            dot(start); dot(end)
        case .radialGradient:
            let center = view(component.center)
            let rx = CGFloat(component.radiusX) * imageRect.width, ry = CGFloat(component.radiusY) * imageRect.height
            line(Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)))
            let inner = max(0.05, 1 - CGFloat(component.feather))
            line(Path(ellipseIn: CGRect(x: center.x - rx * inner, y: center.y - ry * inner, width: rx * inner * 2, height: ry * inner * 2)),
                 width: 1, dashed: true)
            dot(center)
        case .object:
            if let point = component.objectPoint { dot(view(point), 6) }
        case .brush:
            if let hover {
                let radius = CGFloat(model.brushSize) * min(imageRect.width, imageRect.height) / 2
                line(Path(ellipseIn: CGRect(x: hover.x - radius, y: hover.y - radius, width: radius * 2, height: radius * 2)), width: 1.5)
                let core = radius * max(0.08, 1 - CGFloat(model.brushFeather) * 0.8)
                context.stroke(Path(ellipseIn: CGRect(x: hover.x - core, y: hover.y - core, width: core * 2, height: core * 2)),
                               with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if model.brushErases {
                    var minus = Path()
                    minus.move(to: CGPoint(x: hover.x - 5, y: hover.y)); minus.addLine(to: CGPoint(x: hover.x + 5, y: hover.y))
                    line(minus, width: 1.2)
                }
            }
        default:
            break
        }
    }

    private func changed(_ value: DragGesture.Value) {
        if !dragging {
            guard let current = self.kind, imageRect.contains(value.startLocation) else { return }
            dragging = true
            dragKind = current
            let kind = current
            switch kind {
            case .brush: model.beginBrushStroke(at: normalized(value.startLocation))
            case .linearGradient, .radialGradient: model.beginChange()
            default: break
            }
        }
        hover = value.location
        guard let kind = dragKind else { return }
        switch kind {
        case .brush:
            model.continueBrushStroke(at: normalized(value.location))
        case .linearGradient, .radialGradient:
            guard hypot(value.translation.width, value.translation.height) >= 4 else { return }
            model.setGradient(start: normalized(value.startLocation), end: normalized(value.location))
        default:
            break
        }
    }

    private func ended(_ value: DragGesture.Value) {
        defer { dragKind = nil }
        guard dragging, let kind = dragKind else { dragging = false; return }
        dragging = false
        switch kind {
        case .brush: model.endBrushStroke()
        case .linearGradient, .radialGradient: model.endChange()
        case .object, .colorRange:
            if hypot(value.translation.width, value.translation.height) < 4 { model.setMaskPoint(normalized(value.startLocation)) }
        default:
            break
        }
    }
}

// MARK: - Inspector

/// Masks (the list, +, Add / Subtract / Intersect, Show Overlay, Invert),
/// the picked area's own settings, and the mask's adjustments.
struct MacEditorMaskSections: View {
    @Bindable var model: MacEditorModel
    @State private var open: Set<String> = ["masks", "area", "adjust"]
    @State private var expanded: Set<UUID> = []
    @State private var renaming: UUID?
    @State private var newName = ""

    /// The board's + menu, in its order (face parts stay on the iPhone's People row).
    static let addable: [[EditorNewMaskOption]] = [
        [.subject, .sky, .background, .object, .people],
        [.brush, .linearGradient, .radialGradient],
        [.colorRange, .luminanceRange, .depthRange],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacEditorSectionHeader(id: "masks", title: String(localized: "Masks", comment: "Mac editor mask: a group"), open: $open) {
                Menu {
                    optionItems { model.addMask($0) }
                } label: {
                    Label(String(localized: "Add Mask", comment: "Mac editor mask: the + menu"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Add Mask", comment: "Mac editor mask: the + menu"))
                .accessibilityIdentifier("editor.mask.add")
            }
            if open.contains("masks") { maskList }
            Divider()
            if let component = model.selectedComponent, let mask = model.selectedMask {
                MacEditorSectionHeader(id: "area", title: MaskAreaSummary.name(of: component), open: $open) {
                    if component.kind == .brush {
                        // Board: Paint · Erase sits in the Brush head.
                        MacEditorSegments(options: [false, true], selection: $model.brushErases, id: "editor.mask.brushMode") {
                            $0 ? String(localized: "Erase", comment: "Mac editor mask brush") : String(localized: "Paint", comment: "Mac editor mask brush")
                        }
                        .frame(width: 110)
                    }
                }
                if open.contains("area") { MacMaskAreaSettings(model: model, component: component).padding(.bottom, 10) }
                Divider()
                MacEditorSectionHeader(id: "adjust", title: String(localized: "\(mask.name) Adjustments", comment: "Mac editor mask: the mask's sliders"),
                                       open: $open) {
                    if mask.adjustments != .zero {
                        Button { model.updateMask(mask.id) { $0.adjustments = .zero } } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Reset Mask Adjustments", comment: "Mac editor mask"))
                        .accessibilityLabel(String(localized: "Reset Mask Adjustments", comment: "Mac editor mask"))
                        .accessibilityIdentifier("editor.mask.resetAdjustments")
                    }
                }
                if open.contains("adjust") {
                    if !mask.isVisible {
                        Text("This mask is off. Turn it on with its eye to see these changes.", comment: "Mac editor mask: adjusting a hidden mask")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    adjustments(mask).padding(.bottom, 10).opacity(mask.isVisible ? 1 : 0.45)
                }
                Divider()
            }
        }
        // A mask newly picked (added, or picked from the list) shows its areas.
        .onChange(of: model.selectedMaskId) { _, id in if let id { expanded.insert(id) } }
        .onAppear { if let id = model.selectedMaskId { expanded.insert(id) } }
        .alert(String(localized: "Rename Mask", comment: "Mac editor mask: rename alert"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Name", comment: "Mac editor mask: rename field"), text: $newName)
            Button(String(localized: "Rename", comment: "Mac editor mask: confirm rename")) {
                if let id = renaming { model.renameMask(id, to: newName) }
                renaming = nil
            }
            Button(String(localized: "Cancel", comment: "Mac editor mask"), role: .cancel) { renaming = nil }
        }
    }

    // MARK: List

    @ViewBuilder
    private var maskList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.recipe.masks.isEmpty {
                Text("No masks yet. Click + to mask the subject, the sky, a gradient or a painted area.",
                     comment: "Mac editor mask: empty list")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            ForEach(model.recipe.masks) { mask in
                maskRow(mask)
                if expanded.contains(mask.id) {
                    ForEach(mask.components) { component in componentRow(component, in: mask) }
                }
            }
            if model.selectedMask != nil {
                HStack(spacing: 8) {
                    areaMenu(.add)
                    areaMenu(.subtract)
                    areaMenu(.intersect)
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(height: 32)
                HStack {
                    Toggle(String(localized: "Show Overlay", comment: "Mac editor mask: the red overlay"), isOn: $model.showsMaskOverlay)
                        .toggleStyle(.checkbox)
                        .tint(MacTheme.Editor.accent)
                        .accessibilityIdentifier("editor.mask.overlay")
                    RoundedRectangle(cornerRadius: 4).fill(MacTheme.Editor.maskOverlay)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.3)))
                        .frame(width: 18, height: 14)
                        .help(String(localized: "The overlay is drawn in red", comment: "Mac editor mask: the overlay colour swatch"))
                        .accessibilityHidden(true)
                    Spacer()
                    Toggle(String(localized: "Invert Mask", comment: "Mac editor mask: invert the picked mask"),
                           isOn: Binding(get: { model.selectedMask?.isInverted ?? false },
                                         set: { on in if let id = model.selectedMaskId { model.updateMask(id) { $0.isInverted = on } } }))
                        .toggleStyle(.checkbox)
                        .tint(MacTheme.Editor.accent)
                        .accessibilityIdentifier("editor.mask.invert")
                }
                .font(.system(size: 13))
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(height: 26)
            }
        }
        .padding(.bottom, 10)
    }

    private func maskRow(_ mask: PhotoMask) -> some View {
        let isOn = mask.id == model.selectedMaskId
        return HStack(spacing: 8) {
            Button {
                if expanded.contains(mask.id) { expanded.remove(mask.id) } else { expanded.insert(mask.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(mask.id) ? 90 : 0))
                    .frame(width: 12, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Show Areas", comment: "Mac editor mask: expand a mask"))
            thumbnail(model.maskThumbnails[mask.id], symbol: "circle.lefthalf.filled")
            VStack(alignment: .leading, spacing: 1) {
                Text(mask.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(MaskAreaSummary.subtitle(for: mask)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            visibility(isVisible: mask.isVisible, id: "editor.mask.visible") { model.updateMask(mask.id) { $0.isVisible.toggle() } }
        }
        .padding(.leading, 6).padding(.trailing, 6)
        .frame(height: 40)
        .background(isOn ? MacTheme.Editor.rowSelected : Color.clear, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            if mask.id != model.selectedMaskId { model.selectMask(mask.id) }
            expanded.insert(mask.id)
        }
        .padding(.horizontal, 8)
        .contextMenu { maskMenu(mask) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mask.name), \(MaskAreaSummary.subtitle(for: mask))")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.mask.row")
    }

    @ViewBuilder
    private func maskMenu(_ mask: PhotoMask) -> some View {
        Button(String(localized: "Rename Mask…", comment: "Mac editor mask menu")) { newName = mask.name; renaming = mask.id }
        Button(String(localized: "Duplicate Mask", comment: "Mac editor mask menu")) { model.duplicateMask(mask.id) }
        Button(String(localized: "Invert Mask", comment: "Mac editor mask menu")) { model.updateMask(mask.id) { $0.isInverted.toggle() } }
        Toggle(String(localized: "Show Overlay", comment: "Mac editor mask menu"), isOn: $model.showsMaskOverlay)
        Divider()
        ForEach([MaskBlendOperation.add, .subtract, .intersect], id: \.self) { operation in
            Menu(Self.areaTitle(operation)) {
                optionItems { option in model.selectMask(mask.id); model.addArea(option, operation) }
            }
        }
        Divider()
        Button(String(localized: "Reset Mask Adjustments", comment: "Mac editor mask menu")) { model.updateMask(mask.id) { $0.adjustments = .zero } }
            .disabled(mask.adjustments == .zero)
        Button(String(localized: "Delete Mask", comment: "Mac editor mask menu"), role: .destructive) { model.deleteMask(mask.id) }
    }

    static func areaTitle(_ operation: MaskBlendOperation) -> String {
        switch operation {
        case .add: String(localized: "Add Area", comment: "Mac editor mask menu")
        case .subtract: String(localized: "Subtract Area", comment: "Mac editor mask menu")
        case .intersect: String(localized: "Intersect Area", comment: "Mac editor mask menu")
        }
    }

    private func componentRow(_ component: PhotoMaskComponent, in mask: PhotoMask) -> some View {
        let isOn = component.id == model.selectedComponentId && mask.id == model.selectedMaskId
        let detail = [component.operation.displayName, Self.detail(of: component, resolved: model.resolvedAutoAreas, empty: model.emptyAutoAreas)]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 8) {
            // Board: a 16pt disc with the plain sign.
            Image(systemName: component.operation == .subtract ? "minus" : component.operation == .intersect ? "multiply" : "plus")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(MacTheme.Editor.label)
                .frame(width: 16, height: 16)
                .background(MacTheme.Editor.badgeFill, in: Circle())
            thumbnail(nil, symbol: component.kind.systemImage)
            VStack(alignment: .leading, spacing: 1) {
                Text(MaskAreaSummary.name(of: component)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.leading, 28).padding(.trailing, 6)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius)
            .strokeBorder(isOn ? MacTheme.Editor.label : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { model.selectComponent(component.id, in: mask.id) }
        .padding(.horizontal, 8)
        .contextMenu {
            Button(String(localized: "Invert Area", comment: "Mac editor mask area menu")) {
                model.selectComponent(component.id, in: mask.id)
                model.updateComponent(inOneStep: true) { $0.isInverted.toggle() }
            }
            Button(mask.components.count > 1 ? String(localized: "Delete Area", comment: "Mac editor mask area menu")
                                             : String(localized: "Delete Mask", comment: "Mac editor mask: the last area goes with its mask"),
                   role: .destructive) {
                model.deleteComponent(component.id, in: mask.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MaskAreaSummary.name(of: component)), \(detail)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.mask.area")
    }

    /// "detected", "2 strokes", "placed".
    static func detail(of component: PhotoMaskComponent, resolved: Set<UUID>, empty: Set<UUID>) -> String? {
        if empty.contains(component.id) {
            return String(localized: "nothing found", comment: "Mac editor mask: detection came back empty")
        }
        switch component.kind {
        case .subject, .sky, .people, .faceSkin, .eyes, .lips, .depthRange:
            return resolved.contains(component.id) ? String(localized: "detected", comment: "Mac editor mask: an area found by the app")
                : String(localized: "detecting…", comment: "Mac editor mask: an area being found")
        case .brush:
            return component.brushStrokes.isEmpty ? String(localized: "not painted yet", comment: "Mac editor mask: a brush area with no stroke")
                : String(localized: "\(component.brushStrokes.count) strokes", comment: "Mac editor mask: how many brush strokes")
        case .object:
            return component.objectPoint == nil ? String(localized: "click the object", comment: "Mac editor mask: object not picked yet") : nil
        default:
            return component.isInverted ? String(localized: "inverted", comment: "Mac editor mask: an inverted area") : nil
        }
    }

    private func thumbnail(_ image: CGImage?, symbol: String) -> some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.black
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 34, height: 23)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius).strokeBorder(MacTheme.Editor.thumbnailStroke))
    }

    private func visibility(isVisible: Bool, id: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Image(systemName: isVisible ? "eye" : "eye.slash").font(.system(size: 11))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isVisible ? String(localized: "Turn Mask Off", comment: "Mac editor mask") : String(localized: "Turn Mask On", comment: "Mac editor mask"))
        .accessibilityLabel(isVisible ? String(localized: "Turn Mask Off", comment: "Mac editor mask") : String(localized: "Turn Mask On", comment: "Mac editor mask"))
        .accessibilityIdentifier(id)
    }

    private func areaMenu(_ operation: MaskBlendOperation) -> some View {
        Menu {
            optionItems { model.addArea($0, operation) }
        } label: {
            HStack(spacing: 4) {
                Text(operation.displayName).font(.system(size: 12))
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .help(Self.areaTitle(operation))
        .accessibilityIdentifier("editor.mask.\(operation.rawValue)")
    }

    @ViewBuilder
    private func optionItems(_ pick: @escaping (EditorNewMaskOption) -> Void) -> some View {
        ForEach(Array(Self.addable.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group) { option in
                Button { pick(option) } label: { Label(option.title, systemImage: option.systemImage) }
            }
        }
    }

    // MARK: Adjustments

    private func adjustments(_ mask: PhotoMask) -> some View {
        let groups = EditorAdjustmentCatalog.groups(isRAWSource: model.isRAW, scope: .mask)
        let kinds = [EditorAdjustmentGroup.Identity.light, .color, .effects, .detail]
            .flatMap { id in groups.first { $0.id == id }?.kinds ?? [] }
        return VStack(spacing: 0) {
            ForEach(kinds, id: \.self) { kind in
                MacMaskAdjustmentRow(model: model, maskId: mask.id, kind: kind, value: mask.adjustments[kind])
            }
        }
    }
}

/// One of the mask's own sliders: the Light rows' look, writing the mask.
private struct MacMaskAdjustmentRow: View {
    let model: MacEditorModel
    let maskId: UUID
    let kind: PhotoAdjustmentKind
    let value: Double

    var body: some View {
        if EditorAdjustmentCatalog.format(of: kind) == .toggle {
            Toggle(EditorAdjustmentCatalog.shortTitle(of: kind),
                   isOn: Binding(get: { value >= 0.5 }, set: { on in model.updateMask(maskId) { $0.adjustments[kind] = on ? 1 : 0 } }))
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else {
            let range = EditorAdjustmentCatalog.sliderRange(of: kind)
            HStack(spacing: 8) {
                Text(EditorAdjustmentCatalog.shortTitle(of: kind)).font(.system(size: 13)).lineLimit(1).frame(width: 92, alignment: .leading)
                MacEditorSlider(value: value, range: range, isBipolar: EditorAdjustmentCatalog.isBipolar(kind),
                                begin: { model.hidesOverlayWhileAdjusting = true; model.beginChange() },
                                change: { v in model.updateMask(maskId, inOneStep: false) { $0.adjustments[kind] = v } },
                                end: { model.endChange(); model.hidesOverlayWhileAdjusting = false },
                                reset: { model.updateMask(maskId) { $0.adjustments[kind] = PhotoAdjustments.zero[kind] } })
                    .help(String(localized: "Drag to adjust · double-click to reset", comment: "Mac editor slider tooltip"))
                    .accessibilityLabel(EditorAdjustmentCatalog.shortTitle(of: kind))
                    .accessibilityValue(EditorAdjustmentCatalog.displayText(value, of: kind))
                MacEditorNumberField(text: EditorAdjustmentCatalog.displayText(value, of: kind)) { text in
                    guard let entered = EditorAdjustmentCatalog.value(fromDisplayText: text, of: kind) else { return }
                    model.updateMask(maskId) { $0.adjustments[kind] = min(range.upperBound, max(range.lowerBound, entered)) }
                }
                .frame(width: 50)
                .accessibilityLabel(String(localized: "\(EditorAdjustmentCatalog.shortTitle(of: kind)) value", comment: "Mac editor: a slider's number field"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 22)
            .accessibilityIdentifier("editor.mask.slider.\(kind.rawValue)")
        }
    }
}

/// The picked area's own settings: the brush, a gradient's feather, a range.
private struct MacMaskAreaSettings: View {
    @Bindable var model: MacEditorModel
    let component: PhotoMaskComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch component.kind {
            case .brush:
                let short = model.healShortEdgePixels
                MacEditorValueRow(title: String(localized: "Size", comment: "Mac editor mask brush"), value: model.brushSize * short,
                                  range: (0.02 * short)...(0.5 * short), isBipolar: false, format: .pixels, resetValue: 0.12 * short,
                                  id: "editor.mask.brushSize", model: model, change: { value, _ in model.brushSize = value / short })
                MacEditorValueRow(title: String(localized: "Feather", comment: "Mac editor mask brush"), value: model.brushFeather * 100,
                                  range: 0...100, isBipolar: false, resetValue: 45, id: "editor.mask.brushFeather", model: model, change: { value, _ in model.brushFeather = value / 100 })
                MacEditorValueRow(title: String(localized: "Flow", comment: "Mac editor mask brush"), value: model.brushFlow * 100,
                                  range: 5...100, isBipolar: false, resetValue: 80, id: "editor.mask.brushFlow", model: model, change: { value, _ in model.brushFlow = value / 100 })
            case .linearGradient, .radialGradient:
                row(String(localized: "Feather", comment: "Mac editor mask"), component.feather * 100, 0...100, 50, "feather") { $0.feather = $1 / 100 }
            case .luminanceRange:
                row(String(localized: "Darkest", comment: "Mac editor mask: luminance range low end"), component.luminanceMinimum * 100, 0...100, 25, "lumMin") { $0.luminanceMinimum = min($1 / 100, $0.luminanceMaximum) }
                row(String(localized: "Brightest", comment: "Mac editor mask: luminance range high end"), component.luminanceMaximum * 100, 0...100, 75, "lumMax") { $0.luminanceMaximum = max($1 / 100, $0.luminanceMinimum) }
                row(String(localized: "Smoothness", comment: "Mac editor mask: luminance range edge"), component.feather * 100, 0...100, 50, "feather") { $0.feather = $1 / 100 }
            case .colorRange:
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: component.sampledRed, green: component.sampledGreen, blue: component.sampledBlue))
                        .frame(width: 22, height: 22)
                    Text("Click a color in the photo", comment: "Mac editor mask: color range")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 30)
                row(String(localized: "Range", comment: "Mac editor mask: color tolerance"), component.colorTolerance * 100, 1...100, 20, "tolerance") { $0.colorTolerance = $1 / 100 }
            case .depthRange:
                row(String(localized: "Far", comment: "Mac editor mask: depth range far end"), component.depthMinimum * 100, 0...100, 50, "depthMin") { $0.depthMinimum = min($1 / 100, $0.depthMaximum) }
                row(String(localized: "Near", comment: "Mac editor mask: depth range near end"), component.depthMaximum * 100, 0...100, 100, "depthMax") { $0.depthMaximum = max($1 / 100, $0.depthMinimum) }
            default:
                EmptyView()
            }
            row(String(localized: "Opacity", comment: "Mac editor mask: how much of the area"), component.opacity * 100, 1...100, 100, "opacity") { $0.opacity = $1 / 100 }
        }
    }

    private func row(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ reset: Double, _ key: String,
                     _ set: @escaping (inout PhotoMaskComponent, Double) -> Void) -> some View {
        MacEditorValueRow(title: title, value: value, range: range, isBipolar: false, resetValue: reset,
                          id: "editor.mask.area.\(key)", model: model, change: { value, inOneStep in
            model.updateComponent(inOneStep: inOneStep) { set(&$0, value) }
        })
    }
}

/// A group's head in the editor inspector: chevron, title, a trailing control; a click folds it.
struct MacEditorSectionHeader<Trailing: View>: View {
    let id: String
    let title: String
    @Binding var open: Set<String>
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let isOpen = open.contains(id)
        HStack(spacing: 6) {
            Button {
                if isOpen { open.remove(id) } else { open.insert(id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOpen ? String(localized: "Expanded", comment: "Mac editor group, VoiceOver")
                                       : String(localized: "Collapsed", comment: "Mac editor group, VoiceOver"))
            .accessibilityIdentifier("editor.group.\(id)")
            trailing()
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 32)
    }
}
