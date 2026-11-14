import AppKit
import ShotDexKit
import SwiftUI

// MARK: - Frame over the photo

/// The crop frame over the whole straightened photo (board `MAC_EditCrop`):
/// outside dimmed, thirds, L corners and edge bars. Drag a corner or an edge
/// to trim, inside to move. With the Straighten Tool on, a line dragged
/// along something level turns the photo instead.
struct MacEditorCropOverlay: View {
    let model: MacEditorModel
    /// Where the photo is drawn, in this view's space.
    let imageRect: CGRect

    @State private var drag: (handle: CropFrameEditing.Handle, start: NormalizedRect)?
    @State private var ruler: (start: CGPoint, end: CGPoint)?

    private var frame: CGRect {
        let rect = model.recipe.crop.rect
        return CGRect(x: imageRect.minX + rect.x * imageRect.width, y: imageRect.minY + rect.y * imageRect.height,
                      width: rect.width * imageRect.width, height: rect.height * imageRect.height)
    }

    var body: some View {
        let frame = self.frame
        ZStack(alignment: .topLeading) {
            // Outside the frame: dimmed, the photo still read.
            Path { path in
                path.addRect(imageRect.insetBy(dx: -2, dy: -2))
                path.addRect(frame)
            }
            .fill(MacTheme.Editor.cropDim, style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            // Thirds.
            Path { path in
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY)); path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y)); path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(drag == nil ? MacTheme.Editor.cropGrid : MacTheme.Editor.cropGridActive, lineWidth: 1)
            .allowsHitTesting(false)
            Rectangle().stroke(MacTheme.Editor.cropOutline, lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
            MacCropHandles(frame: frame).fill(Color.white).allowsHitTesting(false)
            if model.isStraightening {
                straightenLayer
            } else {
                handleZones(frame)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Crop frame", comment: "Mac editor: the crop frame, VoiceOver"))
        .accessibilityValue(MacEditorCropWords.size(model) ?? "")
    }

    // MARK: Handles

    @ViewBuilder
    private func handleZones(_ frame: CGRect) -> some View {
        // Inside: move. Drawn first, so edges and corners sit over it.
        zone(frame.insetBy(dx: min(MacCropMetrics.moveInset, frame.width / 4), dy: min(MacCropMetrics.moveInset, frame.height / 4)),
             handle: .move, pointer: .grabIdle, id: "editor.crop.frame")
        zone(CGRect(x: frame.minX - 6, y: frame.minY + 14, width: 12, height: max(0, frame.height - 28)),
             handle: .edge(.left), pointer: .frameResize(position: .leading), id: "editor.crop.left")
        zone(CGRect(x: frame.maxX - 6, y: frame.minY + 14, width: 12, height: max(0, frame.height - 28)),
             handle: .edge(.right), pointer: .frameResize(position: .trailing), id: "editor.crop.right")
        zone(CGRect(x: frame.minX + 14, y: frame.minY - 6, width: max(0, frame.width - 28), height: 12),
             handle: .edge(.top), pointer: .frameResize(position: .top), id: "editor.crop.top")
        zone(CGRect(x: frame.minX + 14, y: frame.maxY - 6, width: max(0, frame.width - 28), height: 12),
             handle: .edge(.bottom), pointer: .frameResize(position: .bottom), id: "editor.crop.bottom")
        ForEach([false, true], id: \.self) { right in
            ForEach([false, true], id: \.self) { bottom in
                zone(CGRect(x: (right ? frame.maxX : frame.minX) - 12, y: (bottom ? frame.maxY : frame.minY) - 12, width: 24, height: 24),
                     handle: .corner(right: right, bottom: bottom),
                     pointer: .frameResize(position: right ? (bottom ? .bottomTrailing : .topTrailing) : (bottom ? .bottomLeading : .topLeading)),
                     id: "editor.crop.corner.\(bottom ? "bottom" : "top")\(right ? "Right" : "Left")")
            }
        }
    }

    private func zone(_ rect: CGRect, handle: CropFrameEditing.Handle, pointer: PointerStyle, id: String) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .pointerStyle(pointer)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(MacEditorCropOverlay.space))
                .onChanged { value in
                    if drag == nil {
                        drag = (handle, model.recipe.crop.rect)
                        model.beginChange()
                    }
                    guard let drag, imageRect.width > 0, imageRect.height > 0 else { return }
                    model.dragCrop(drag.handle, from: drag.start,
                                   dx: Double(value.translation.width / imageRect.width),
                                   dy: Double(value.translation.height / imageRect.height))
                }
                .onEnded { _ in
                    drag = nil
                    model.endChange()
                })
            .offset(x: rect.minX, y: rect.minY)
            .accessibilityElement()
            .accessibilityLabel(id.replacingOccurrences(of: "editor.crop.", with: ""))
            .accessibilityIdentifier(id)
    }

    static let space = "editor.crop"

    // MARK: Straighten Tool

    private var straightenLayer: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .pointerStyle(.rectSelection)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacEditorCropOverlay.space))
                    .onChanged { value in ruler = (value.startLocation, value.location) }
                    .onEnded { value in
                        ruler = nil
                        if let correction = StraightenToolMath.correction(from: value.startLocation, to: value.location) {
                            model.straighten(byRuler: correction)
                        }
                    })
                .accessibilityIdentifier("editor.straighten.canvas")
            if let ruler {
                Path { path in path.move(to: ruler.start); path.addLine(to: ruler.end) }
                    .stroke(MacTheme.Editor.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .allowsHitTesting(false)
            }
            Text("Drag along something that should be level", comment: "Mac editor: the Straighten Tool's hint over the photo")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Editor.label)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(MacTheme.Editor.glass, in: Capsule())
                .overlay(Capsule().strokeBorder(MacTheme.Editor.glassStroke))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .allowsHitTesting(false)
        }
    }
}

/// Board sizes: L corners 22 long and 4 thick, flush outside the line;
/// 24×3 bars at each edge's middle, on the line.
enum MacCropMetrics {
    static let cornerLength: CGFloat = 22
    static let cornerThickness: CGFloat = 4
    static let barLength: CGFloat = 24
    static let barThickness: CGFloat = 3
    /// Grab zones: corners 24 square, edges 12 deep, the move area inset 10.
    static let cornerZone: CGFloat = 24
    static let edgeZone: CGFloat = 12
    static let moveInset: CGFloat = 10
}

private struct MacCropHandles: Shape {
    let frame: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        let length = MacCropMetrics.cornerLength, thickness = MacCropMetrics.cornerThickness
        let outer = frame.insetBy(dx: -thickness, dy: -thickness)
        for (right, bottom) in [(false, false), (true, false), (false, true), (true, true)] {
            let x = right ? outer.maxX - length : outer.minX
            let y = bottom ? outer.maxY - thickness : outer.minY
            path.addRect(CGRect(x: x, y: y, width: length, height: thickness))
            path.addRect(CGRect(x: right ? outer.maxX - thickness : outer.minX, y: bottom ? outer.maxY - length : outer.minY,
                                width: thickness, height: length))
        }
        let bar = MacCropMetrics.barLength, barThickness = MacCropMetrics.barThickness
        path.addRect(CGRect(x: frame.midX - bar / 2, y: frame.minY - barThickness, width: bar, height: barThickness))
        path.addRect(CGRect(x: frame.midX - bar / 2, y: frame.maxY, width: bar, height: barThickness))
        path.addRect(CGRect(x: frame.minX - barThickness, y: frame.midY - bar / 2, width: barThickness, height: bar))
        path.addRect(CGRect(x: frame.maxX, y: frame.midY - bar / 2, width: barThickness, height: bar))
        return path
    }
}

// MARK: - Inspector

/// Crop's inspector (board `MAC_EditCrop`): Crop (Aspect, lock, ⇅, size,
/// turn and mirror), Straighten (Angle, Straighten Tool, Auto), Upright
/// (Mode) and Geometry (the shared Geo sliders, Constrain Crop).
struct MacEditorCropSections: View {
    @Bindable var model: MacEditorModel
    @State private var open: Set<String> = ["crop", "straighten", "upright", "geometry"]

    /// ↺ shows while there is something to put back: a straightened photo's
    /// whole frame is the largest that fits, not `.full`.
    private var cropIsChanged: Bool {
        let crop = model.recipe.crop
        if crop.quarterTurns != 0 || crop.flippedHorizontally || crop.aspect != .free { return true }
        let whole = model.cropEditing?.fitted(.full) ?? .full
        return abs(crop.rect.x - whole.x) > 1e-6 || abs(crop.rect.y - whole.y) > 1e-6
            || abs(crop.rect.width - whole.width) > 1e-6 || abs(crop.rect.height - whole.height) > 1e-6
    }

    private var geometryKinds: [PhotoAdjustmentKind] {
        EditorAdjustmentCatalog.groups(isRAWSource: model.isRAW, scope: .global).first { $0.id == .geo }?.kinds ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("crop", String(localized: "Crop", comment: "Mac editor crop: a group"),
                    reset: cropIsChanged ? { model.resetCrop() } : nil) {
                cropRows
            }
            Divider()
            section("straighten", String(localized: "Straighten", comment: "Mac editor crop: a group"),
                    reset: model.recipe.crop.straightenDegrees != 0 ? { model.resetStraighten() } : nil) {
                straightenRows
            }
            Divider()
            section("upright", String(localized: "Upright", comment: "Mac editor crop: a group"), reset: nil) {
                uprightRows
            }
            Divider()
            section("geometry", String(localized: "Geometry", comment: "Mac editor crop: a group"),
                    reset: geometryKinds.contains { model.recipe.adjustments[$0] != PhotoAdjustments.zero[$0] } ? {
                        let kinds = geometryKinds
                        model.apply { recipe in for kind in kinds { recipe.adjustments[kind] = PhotoAdjustments.zero[kind] } }
                    } : nil) {
                VStack(spacing: 0) {
                    ForEach(geometryKinds, id: \.self) { kind in
                        MacEditorSliderRow(model: model, kind: kind)
                    }
                }
                .tint(MacTheme.Editor.accent)
                .padding(.bottom, 8)
            }
            Divider()
        }
    }

    // MARK: Crop

    private var cropRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                label(String(localized: "Aspect", comment: "Mac editor crop: the ratio row"))
                Picker(String(localized: "Aspect", comment: "Mac editor crop: the ratio row"),
                       selection: Binding(get: { model.recipe.crop.aspect }, set: { model.chooseAspect($0) })) {
                    Text(MacEditorCropWords.aspectTitle(.free, model: model)).tag(CropAspect.free)
                    Text(MacEditorCropWords.aspectTitle(.original, model: model)).tag(CropAspect.original)
                    Divider()
                    ForEach(CropAspect.allCases.filter { $0 != .free && $0 != .original }) { aspect in
                        Text(aspect.displayName).tag(aspect)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("editor.crop.aspect")
                iconButton(model.isAspectLocked ? "lock.fill" : "lock.open",
                           label: model.isAspectLocked ? String(localized: "Unlock Aspect", comment: "Mac editor crop: lets the frame go free")
                                                       : String(localized: "Lock Aspect", comment: "Mac editor crop: holds the frame's ratio"),
                           isOn: model.isAspectLocked, id: "editor.crop.lock") { model.toggleAspectLock() }
                iconButton("arrow.up.arrow.down",
                           label: String(localized: "Swap Width and Height", comment: "Mac editor crop: 3:2 becomes 2:3"),
                           id: "editor.crop.swap") { model.swapAspect() }
                    .disabled(model.swappedAspect == nil || (model.recipe.crop.aspect != .free && model.swappedAspect == model.recipe.crop.aspect))
            }
            HStack(spacing: 8) {
                label(String(localized: "Size", comment: "Mac editor crop: the cropped size row"))
                Text(MacEditorCropWords.size(model) ?? "—")
                    .font(.system(size: 13).monospacedDigit())
                    .accessibilityIdentifier("editor.crop.size")
                Spacer(minLength: 4)
                Text(MacEditorCropWords.percent(model) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                iconButton("arrow.counterclockwise", label: String(localized: "Rotate Left", comment: "Mac editor crop"), id: "editor.crop.rotateLeft") {
                    model.turn(clockwise: false)
                }
                iconButton("arrow.clockwise", label: String(localized: "Rotate Right", comment: "Mac editor crop"), id: "editor.crop.rotateRight") {
                    model.turn(clockwise: true)
                }
                Spacer().frame(width: 6)
                iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right",
                           label: String(localized: "Flip Horizontal", comment: "Mac editor crop"), id: "editor.crop.flipH") {
                    model.flip(vertically: false)
                }
                iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down",
                           label: String(localized: "Flip Vertical", comment: "Mac editor crop"), id: "editor.crop.flipV") {
                    model.flip(vertically: true)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Straighten

    private var straightenRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Angle", comment: "Mac editor crop: the straighten angle")
                    .font(.system(size: 13))
                    .frame(width: 92, alignment: .leading)
                MacEditorSlider(value: model.recipe.crop.straightenDegrees, range: -45...45, isBipolar: true,
                                begin: model.beginChange, change: { model.straighten(to: $0) }, end: model.endChange,
                                reset: { model.resetStraighten() })
                    .help(String(localized: "Drag to adjust · double-click to reset", comment: "Mac editor slider tooltip"))
                    .accessibilityLabel(String(localized: "Angle", comment: "Mac editor crop: the straighten angle"))
                    .accessibilityValue(MacEditorCropWords.degrees(model.recipe.crop.straightenDegrees))
                MacEditorNumberField(text: MacEditorCropWords.degrees(model.recipe.crop.straightenDegrees)) { text in
                    let cleaned = text.replacingOccurrences(of: "°", with: "")
                        .replacingOccurrences(of: "\u{2212}", with: "-")
                        .trimmingCharacters(in: .whitespaces)
                    // Read as shown ("2,4" where the comma is the decimal), then plainly.
                    guard let value = (try? Double(cleaned, format: .number)) ?? Double(cleaned) else { return }
                    model.straighten(to: value, inOneStep: true)
                }
                .frame(width: 50)
                .accessibilityLabel(String(localized: "Angle value", comment: "Mac editor crop"))
                .accessibilityIdentifier("editor.crop.angleValue")
            }
            HStack(spacing: 8) {
                wideButton(String(localized: "Straighten Tool", comment: "Mac editor crop: draw a level line"), systemImage: "ruler",
                           isOn: model.isStraightening, id: "editor.crop.straightenTool") {
                    model.isStraightening.toggle()
                }
                .help(String(localized: "Drag along something level in the photo", comment: "Mac editor crop: Straighten Tool tooltip"))
                wideButton(String(localized: "Auto", comment: "Mac editor crop: level the photo automatically"), systemImage: "wand.and.rays",
                           isOn: false, isBusy: model.isAnalyzing && !model.analyzingUpright, id: "editor.crop.auto") {
                    model.autoStraighten()
                }
                .disabled(model.isAnalyzing)
                .help(String(localized: "Level the horizon from the photo itself", comment: "Mac editor crop: Auto tooltip"))
            }
            if let text = model.straightenNote { noteText(text) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
    }

    // MARK: Upright

    private var uprightRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                label(String(localized: "Mode", comment: "Mac editor crop: Upright's mode"))
                Picker(String(localized: "Upright", comment: "Mac editor crop: a group"),
                       selection: Binding(get: { model.recipe.upright.mode }, set: { model.setUpright($0) })) {
                    ForEach(PhotoUprightMode.allCases.filter { $0 != .guided }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                    if model.recipe.upright.mode == .guided {
                        Text(PhotoUprightMode.guided.displayName).tag(PhotoUprightMode.guided)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("editor.crop.upright")
                if model.analyzingUpright {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel(String(localized: "Reading the photo", comment: "Mac editor crop: Upright is analysing"))
                }
            }
            Text("Straightens converging lines from the photo itself.", comment: "Mac editor crop: what Upright does")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let text = model.uprightNote { noteText(text) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Pieces

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(MacTheme.Editor.accent)
            .accessibilityIdentifier("editor.crop.note")
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
    }

    private func iconButton(_ systemImage: String, label: String, isOn: Bool = false, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(width: 32, height: 26)
                .background(isOn ? MacTheme.Editor.pressed : MacTheme.Editor.control,
                            in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func wideButton(_ title: String, systemImage: String, isOn: Bool, isBusy: Bool = false, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy { ProgressView().controlSize(.mini) }
                Label(title, systemImage: systemImage)
            }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(isOn ? MacTheme.Editor.pressed : MacTheme.Editor.control, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius).strokeBorder(isOn ? MacTheme.Editor.label.opacity(0.5) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func section<Content: View>(_ id: String, _ title: String, reset: (() -> Void)?,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if isOpen { open.remove(id) } else { open.insert(id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isOpen ? String(localized: "Expanded", comment: "Mac editor group, VoiceOver")
                                           : String(localized: "Collapsed", comment: "Mac editor group, VoiceOver"))
                .accessibilityIdentifier("editor.group.\(id)")
                if let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Reset \(title)", comment: "Mac editor: reset one group"))
                    .accessibilityLabel(String(localized: "Reset \(title)", comment: "Mac editor: reset one group"))
                    .accessibilityIdentifier("editor.reset.\(id)")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
            if isOpen { content() }
        }
    }
}

// MARK: - Words

enum MacEditorCropWords {
    /// "Original · 3:2", "Free".
    @MainActor
    static func aspectTitle(_ aspect: CropAspect, model: MacEditorModel) -> String {
        guard aspect == .original, let editing = model.cropEditing,
              let preset = CropFrameEditing.preset(matching: editing.photoAspect) else { return aspect.displayName }
        return String(localized: "Original · \(preset.displayName)", comment: "Mac editor crop: the photo's own ratio, named")
    }

    /// "5712 × 3808 px".
    @MainActor
    static func size(_ model: MacEditorModel) -> String? {
        guard let editing = model.cropEditing else { return nil }
        let size = editing.pixelSize(of: model.recipe.crop.rect)
        return String(localized: "\(size.width.formatted(.number.grouping(.never))) × \(size.height.formatted(.number.grouping(.never))) px",
                      comment: "Mac editor crop: the cropped size in pixels")
    }

    /// "87% of original".
    @MainActor
    static func percent(_ model: MacEditorModel) -> String? {
        guard let editing = model.cropEditing else { return nil }
        let percent = editing.pixelSize(of: model.recipe.crop.rect).percent
        return String(localized: "\(percent)% of original", comment: "Mac editor crop: how much of the photo the crop keeps")
    }

    /// "+2.4°", "0.0°".
    static func degrees(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(1)))
        return value > 0.04 ? "+\(text)°" : "\(text)°"
    }
}
