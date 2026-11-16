import ShotDexKit
import SwiftUI

// MARK: - Over the photo

/// Heal on the canvas (board `MAC_EditHeal`, FS-18.03 §1d): a click makes a
/// spot filled from beside it, a drag paints a brush-stroke spot; a spot's
/// circle drags it, its dashed source circle drags the source. Red Eye: a
/// click darkens the pupil near it. The brush follows the pointer, its
/// feather as a dashed ring.
struct MacEditorHealOverlay: View {
    @Bindable var model: MacEditorModel
    let imageRect: CGRect

    private enum Grab: Equatable {
        case spot(UUID, start: NormalizedPoint)
        case source(UUID, start: NormalizedPoint)
        case redEye(UUID, start: NormalizedPoint)
        case paint
    }

    @State private var grab: Grab?
    @State private var stroke: [CGPoint] = []
    @State private var hover: CGPoint?

    /// Radius (fraction of the short edge) in points on screen.
    private func points(_ radius: Double) -> CGFloat { CGFloat(radius) * min(imageRect.width, imageRect.height) }

    private func view(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + CGFloat(point.x) * imageRect.width, y: imageRect.minY + CGFloat(point.y) * imageRect.height)
    }

    private func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: Double((point.x - imageRect.minX) / max(1, imageRect.width)),
                        y: Double((point.y - imageRect.minY) / max(1, imageRect.height)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.visualizesSpots, let map = model.spotMap {
                Image(decorative: map, scale: 1).resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Canvas { context, _ in draw(in: &context) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: imageRect.width, height: imageRect.height)
                .onContinuousHover(coordinateSpace: .named(MacEditorCropOverlay.space)) { phase in
                    if case .active(let point) = phase, imageRect.contains(point) { hover = point } else { hover = nil }
                }
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MacEditorCropOverlay.space))
                    .onChanged(changed)
                    .onEnded(ended))
                // A hand over a spot or a source (they move), the brush elsewhere.
                .pointerStyle(grab != nil && grab != .paint ? .grabActive : (hover.flatMap(hit) != nil ? .grabIdle : .rectSelection))
                .accessibilityElement()
                .accessibilityLabel(model.healMode == .redEye
                                    ? String(localized: "Photo, click a red eye", comment: "Mac editor heal canvas, VoiceOver")
                                    : String(localized: "Photo, click or paint over a spot to remove it", comment: "Mac editor heal canvas, VoiceOver"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("editor.heal.canvas")
                .position(x: imageRect.midX, y: imageRect.midY)
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext) {
        let white = GraphicsContext.Shading.color(.white)
        let shadow = GraphicsContext.Shading.color(MacTheme.Editor.overlayHalo)
        func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        func outline(_ path: Path, dashed: Bool = false, width: CGFloat = 1.5) {
            let style = StrokeStyle(lineWidth: width, dash: dashed ? [5, 4] : [])
            context.stroke(path, with: shadow, style: StrokeStyle(lineWidth: width + 1.5, dash: style.dash))
            context.stroke(path, with: white, style: style)
        }
        func strokePath(_ spot: PhotoHealingSpot, at origin: NormalizedPoint) -> Path {
            var path = Path()
            for (i, p) in (spot.stroke ?? []).enumerated() {
                let point = view(NormalizedPoint(x: origin.x + p.x, y: origin.y + p.y))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            return path
        }
        if model.healMode == .redEye {
            for eye in model.recipe.redEyes where model.showsSpotPins || eye.id == model.selectedRedEyeId {
                let isOn = eye.id == model.selectedRedEyeId
                outline(circle(view(eye.center), points(eye.radius)), width: isOn ? 2 : 1.5)
            }
        } else {
            for spot in model.recipe.healing where !model.hiddenSpotIds.contains(spot.id) || spot.id == model.selectedSpotId {
                let isOn = spot.id == model.selectedSpotId
                guard isOn || model.showsSpotPins else { continue }
                let center = view(spot.center)
                if spot.stroke != nil {
                    let width = points(spot.radius) * 2
                    context.stroke(strokePath(spot, at: spot.center), with: .color(.white.opacity(isOn ? 0.3 : 0.2)),
                                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    outline(strokePath(spot, at: spot.center), width: 1.4)
                } else if isOn {
                    outline(circle(center, points(spot.radius)), width: 2.6)
                } else {
                    // Board: a spot not picked is its circle, thinner.
                    outline(circle(center, points(spot.radius)), width: 1.6)
                    continue
                }
                guard isOn else { continue }
                // The picked spot: its source dashed, joined to it, a dot in the middle.
                let source = view(spot.source)
                if spot.stroke != nil {
                    outline(strokePath(spot, at: spot.source), dashed: true, width: 2)
                } else {
                    outline(circle(source, points(spot.radius)), dashed: true, width: 2)
                    var join = Path()
                    let r = points(spot.radius)
                    let dx = center.x - source.x, dy = center.y - source.y, length = max(1, hypot(dx, dy))
                    join.move(to: CGPoint(x: source.x + dx / length * r, y: source.y + dy / length * r))
                    join.addLine(to: CGPoint(x: center.x - dx / length * r, y: center.y - dy / length * r))
                    if length > r * 2 { outline(join, width: 1.4) }
                    context.fill(circle(center, 3), with: white)
                }
            }
        }
        // The stroke being painted.
        if grab == .paint, stroke.count > 1 {
            var path = Path()
            path.addLines(stroke)
            context.stroke(path, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: points(model.healRadius) * 2, lineCap: .round, lineJoin: .round))
        }
        // The brush under the pointer: its size, its feather dashed outside it.
        if let hover, grab == nil, hit(hover) == nil {
            let radius = model.healMode == .redEye ? points(0.02) : points(model.healRadius)
            outline(circle(hover, radius), width: 1.5)
            if model.healMode != .redEye {
                // The feather blends inward: full strength inside this ring (the kernel's inner edge).
                let ring = circle(hover, radius * max(0.05, 1 - CGFloat(model.healFeather) * 0.7))
                context.stroke(ring, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            var plus = Path()
            plus.move(to: CGPoint(x: hover.x - 5, y: hover.y)); plus.addLine(to: CGPoint(x: hover.x + 5, y: hover.y))
            plus.move(to: CGPoint(x: hover.x, y: hover.y - 5)); plus.addLine(to: CGPoint(x: hover.x, y: hover.y + 5))
            outline(plus, width: 1.2)
        }
    }

    // MARK: Gestures

    private func hit(_ point: CGPoint) -> Grab? {
        if model.healMode == .redEye {
            let found = model.recipe.redEyes.last { hypot(view($0.center).x - point.x, view($0.center).y - point.y) <= max(8, points($0.radius)) }
            return found.map { .redEye($0.id, start: $0.center) }
        }
        // The picked spot's source first (it may sit over another spot), then any spot.
        if let spot = model.selectedSpot,
           hypot(view(spot.source).x - point.x, view(spot.source).y - point.y) <= max(8, points(spot.radius)) {
            return .source(spot.id, start: spot.source)
        }
        let found = model.recipe.healing.last { spot in
            (!model.hiddenSpotIds.contains(spot.id) || spot.id == model.selectedSpotId)
                && distance(from: point, to: spot) <= max(8, points(spot.radius))
        }
        return found.map { .spot($0.id, start: $0.center) }
    }

    /// To a round spot's centre, or to the nearest stretch of a painted one.
    private func distance(from point: CGPoint, to spot: PhotoHealingSpot) -> CGFloat {
        guard let stroke = spot.stroke, stroke.count > 1 else {
            return hypot(view(spot.center).x - point.x, view(spot.center).y - point.y)
        }
        let line = stroke.map { view(NormalizedPoint(x: spot.center.x + $0.x, y: spot.center.y + $0.y)) }
        var best = CGFloat.greatestFiniteMagnitude
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / max(0.0001, dx * dx + dy * dy)))
            best = min(best, hypot(a.x + t * dx - point.x, a.y + t * dy - point.y))
        }
        return best
    }

    private func changed(_ value: DragGesture.Value) {
        if grab == nil {
            guard imageRect.contains(value.startLocation) else { return }
            if let found = hit(value.startLocation) {
                grab = found
                switch found {
                case .spot(let id, _), .source(let id, _): model.selectSpot(id)
                case .redEye(let id, _): model.selectRedEye(id)
                case .paint: break
                }
                model.beginChange()
            } else {
                grab = .paint
                stroke = [value.startLocation]
            }
        }
        let dx = Double(value.translation.width / max(1, imageRect.width))
        let dy = Double(value.translation.height / max(1, imageRect.height))
        func moved(_ start: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(x: min(1, max(0, start.x + dx)), y: min(1, max(0, start.y + dy)))
        }
        switch grab {
        case .spot(let id, let start): model.updateSpot(id) { $0.center = moved(start) }
        case .source(let id, let start): model.updateSpot(id) { $0.source = moved(start) }
        case .redEye(let id, let start): model.updateRedEye(id) { $0.center = moved(start) }
        case .paint:
            let point = CGPoint(x: min(imageRect.maxX, max(imageRect.minX, value.location.x)),
                                y: min(imageRect.maxY, max(imageRect.minY, value.location.y)))
            if let last = stroke.last, hypot(last.x - point.x, last.y - point.y) >= 2 { stroke.append(point) }
        case nil: break
        }
    }

    private func ended(_ value: DragGesture.Value) {
        defer { grab = nil; stroke = [] }
        switch grab {
        case .spot, .source, .redEye:
            model.endChange()
        case .paint:
            let travel = hypot(value.translation.width, value.translation.height)
            // A click on empty photo with something picked lets go of it; the next click adds.
            if travel < 4, model.healMode == .redEye ? model.selectedRedEyeId != nil : model.selectedSpotId != nil {
                model.selectSpot(nil)
                model.selectRedEye(nil)
                return
            }
            if model.healMode == .redEye {
                model.addRedEye(at: normalized(value.startLocation))
            } else if travel < 4 || stroke.count < 2 {
                // A click: a round spot. (Clicking a spot selects it — handled above.)
                model.addSpot(at: normalized(value.startLocation))
            } else {
                model.addStroke(through: stroke.map(normalized))
            }
        case nil:
            break
        }
    }
}

// MARK: - Inspector

/// Retouch (Heal · Clone · Red Eye, Size · Feather · Opacity), Spots (the
/// list, New Source, Delete Spot, Clear All…), View (Visualize Spots,
/// Threshold, Show Spot Pins).
struct MacEditorHealSections: View {
    @Bindable var model: MacEditorModel
    @State private var asksClear = false
    @State private var open: Set<String> = ["retouch", "spots", "view"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("retouch", String(localized: "Retouch", comment: "Mac editor heal: a group"), trailing: Text(editingWhat)
                .font(.system(size: 11)).foregroundStyle(.secondary).accessibilityIdentifier("editor.heal.editing"))
            if open.contains("retouch") { VStack(alignment: .leading, spacing: 4) {
                MacEditorSegments(options: MacEditorModel.HealMode.allCases,
                                  selection: Binding(get: { model.healMode }, set: { model.setHealMode($0) }),
                                  id: "editor.heal.mode") { Self.title($0) }
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                if model.healMode == .redEye {
                    row(String(localized: "Pupil", comment: "Mac editor heal: red eye"), \.redEyePupil, range: 5...100, reset: 50, id: "pupil")
                    row(String(localized: "Darken", comment: "Mac editor heal: red eye"), \.redEyeDarken, range: 0...100, reset: 50, id: "darken")
                    Button { model.fixRedEyes() } label: {
                        HStack(spacing: 6) {
                            if model.isLocatingEyes { ProgressView().controlSize(.mini) }
                            Label(String(localized: "Fix Red Eye", comment: "Mac editor heal: find and fix every red pupil"), systemImage: "eye")
                        }
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .disabled(model.isLocatingEyes)
                    .accessibilityIdentifier("editor.heal.fixRedEye")
                } else {
                    // In the photo's own pixels (the radius on the cropped frame's short edge).
                    let short = model.healShortEdgePixels
                    MacEditorValueRow(
                        title: String(localized: "Size", comment: "Mac editor heal"), value: model.healRadius * short,
                        range: (0.005 * short)...(0.15 * short), isBipolar: false, format: .pixels, resetValue: 0.03 * short,
                        id: "editor.heal.size", model: model,
                        change: { value, inOneStep in model.setHealValue(\.healRadius, value / short, inOneStep: inOneStep) })
                    row(String(localized: "Feather", comment: "Mac editor heal"), \.healFeather, range: 0...100, reset: 50, id: "feather")
                    row(String(localized: "Opacity", comment: "Mac editor heal"), \.healOpacity, range: 0...100, reset: 100, id: "opacity")
                }
            }
            .padding(.bottom, 10)
            }
            Divider()
            spots
            Divider()
            view
            Divider()
        }
        .confirmationDialog(model.healMode == .redEye
                            ? String(localized: "Remove every red eye fix from this photo?", comment: "Mac editor heal: Clear All… asks, Red Eye")
                            : String(localized: "Remove every spot from this photo?", comment: "Mac editor heal: Clear All… asks"),
                            isPresented: $asksClear) {
            Button(String(localized: "Clear All", comment: "Mac editor heal: confirm"), role: .destructive) { model.clearAllSpots() }
        } message: {
            Text("⌘Z brings them back.", comment: "Mac editor heal: Clear All… is undoable")
        }
    }

    /// Whose settings the sliders are: the picked spot's, or the next one's.
    private var editingWhat: String {
        if model.healMode == .redEye {
            guard let index = model.recipe.redEyes.firstIndex(where: { $0.id == model.selectedRedEyeId }) else {
                return String(localized: "New eyes", comment: "Mac editor heal: the sliders set the next red eye")
            }
            return String(localized: "Eye \(index + 1)", comment: "Mac editor heal: the sliders edit this eye")
        }
        guard let index = model.recipe.healing.firstIndex(where: { $0.id == model.selectedSpotId }) else {
            return String(localized: "New spots", comment: "Mac editor heal: the sliders set the next spot")
        }
        return String(localized: "Spot \(index + 1)", comment: "Mac editor heal: the sliders edit this spot")
    }

    static func title(_ mode: MacEditorModel.HealMode) -> String {
        switch mode {
        case .heal: String(localized: "Heal", comment: "Mac editor heal mode")
        case .clone: String(localized: "Clone", comment: "Mac editor heal mode")
        case .redEye: String(localized: "Red Eye", comment: "Mac editor heal mode")
        }
    }

    private func row(_ title: String, _ key: ReferenceWritableKeyPath<MacEditorModel, Double>, range: ClosedRange<Double>, reset: Double, id: String) -> some View {
        MacEditorValueRow(
            title: title, value: model[keyPath: key] * 100, range: range, isBipolar: false, resetValue: reset,
            id: "editor.heal.\(id)", model: model,
            change: { value, inOneStep in model.setHealValue(key, value / 100, inOneStep: inOneStep) })
    }

    private func header(_ id: String, _ title: String) -> some View { header(id, title, trailing: EmptyView()) }

    /// Board: chevron then title, 32 tall, 14 in; a click folds the group.
    private func header<Trailing: View>(_ id: String, _ title: String, trailing: Trailing) -> some View {
        let isOpen = open.contains(id)
        return HStack(spacing: 6) {
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
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 32)
    }

    // MARK: Spots

    private var count: Int { model.healMode == .redEye ? model.recipe.redEyes.count : model.recipe.healing.count }

    private var spots: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("spots", model.healMode == .redEye ? String(localized: "Eyes", comment: "Mac editor heal: the red eye list")
                                                      : String(localized: "Spots", comment: "Mac editor heal: a group"),
                   trailing: HStack(spacing: 4) {
                       Text(count.formatted()).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                       Button(String(localized: "Clear All…", comment: "Mac editor heal: remove every spot")) { asksClear = true }
                           .buttonStyle(.plain)
                           .font(.system(size: 12, weight: .medium))
                           .padding(.horizontal, 8)
                           .frame(height: 22)
                           .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                           .disabled(count == 0)
                           .accessibilityIdentifier("editor.heal.clearAll")
                   })
            if open.contains("spots") { spotRows }
        }
        .padding(.bottom, open.contains("spots") ? 10 : 0)
    }

    @ViewBuilder
    private var spotRows: some View {
            if model.healMode == .redEye {
                ForEach(Array(model.recipe.redEyes.enumerated()), id: \.element.id) { index, eye in
                    listRow(title: String(localized: "Eye \(index + 1)", comment: "Mac editor heal: one red eye"),
                            detail: Self.place(eye.center), center: eye.center, radius: eye.radius,
                            isOn: eye.id == model.selectedRedEyeId, hiddenId: nil) { model.selectRedEye(eye.id) }
                }
            } else {
                ForEach(Array(model.recipe.healing.enumerated()), id: \.element.id) { index, spot in
                    listRow(title: String(localized: "Spot \(index + 1)", comment: "Mac editor heal: one spot"),
                            detail: [spot.mode.displayName,
                                     spot.stroke == nil ? String(localized: "circle", comment: "Mac editor heal: a round spot")
                                                        : String(localized: "brush stroke", comment: "Mac editor heal: a painted spot"),
                                     Self.place(spot.center)].joined(separator: " · "),
                            center: spot.center, radius: spot.radius,
                            isOn: spot.id == model.selectedSpotId, hiddenId: spot.id) { model.selectSpot(spot.id) }
                }
            }
            if count == 0 {
                Text(model.healMode == .redEye
                     ? "Click a red pupil in the photo, or Fix Red Eye to find them all."
                     : "Click a spot in the photo to remove it, or drag to paint over a line.",
                     comment: "Mac editor heal: empty list")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if model.healMode != .redEye, model.selectedSpot != nil {
                Text("Drag the dashed outline to fill from somewhere else.", comment: "Mac editor heal: how to move a source")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if let note = model.healNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("editor.heal.note")
            }
            HStack(spacing: 8) {
                if model.healMode != .redEye {
                    wide(model.isFindingSource ? String(localized: "Finding…", comment: "Mac editor heal: New Source is looking")
                                               : String(localized: "New Source", comment: "Mac editor heal: move the source somewhere better"),
                         "arrow.triangle.2.circlepath", id: "editor.heal.newSource") { model.findNewSource() }
                        .disabled(model.selectedSpot == nil || model.isFindingSource)
                        .help(String(localized: "Fill the spot from another place nearby", comment: "Mac editor heal: New Source tooltip"))
                }
                wide(String(localized: "Delete Spot", comment: "Mac editor heal: remove the selected spot"), "trash", id: "editor.heal.delete") {
                    model.deleteSelectedSpot()
                }
                .disabled(model.healMode == .redEye ? model.selectedRedEye == nil : model.selectedSpot == nil)
                .help(String(localized: "Select a spot to delete it (or press Delete)", comment: "Mac editor heal: Delete Spot tooltip"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, 4)
    }

    /// "top left", "center", "bottom right".
    static func place(_ point: NormalizedPoint) -> String {
        let row = point.y < 1.0 / 3 ? String(localized: "top", comment: "Mac editor heal: where a spot is")
            : point.y > 2.0 / 3 ? String(localized: "bottom", comment: "Mac editor heal: where a spot is") : ""
        let column = point.x < 1.0 / 3 ? String(localized: "left", comment: "Mac editor heal: where a spot is")
            : point.x > 2.0 / 3 ? String(localized: "right", comment: "Mac editor heal: where a spot is") : ""
        let words = [row, column].filter { !$0.isEmpty }
        return words.isEmpty ? String(localized: "center", comment: "Mac editor heal: where a spot is") : words.joined(separator: " ")
    }

    private func listRow(title: String, detail: String, center: NormalizedPoint, radius: Double, isOn: Bool, hiddenId: UUID?,
                         select: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            MacHealThumbnail(image: model.samplingImage, center: center, radius: radius)
                .frame(width: 34, height: 23)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let hiddenId {
                let hidden = model.hiddenSpotIds.contains(hiddenId)
                Button { model.toggleHidden(hiddenId) } label: {
                    Image(systemName: hidden ? "circle.slash" : "circle.dashed").font(.system(size: 11))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(hidden ? String(localized: "Show Outline", comment: "Mac editor heal: draw this spot's circle again")
                             : String(localized: "Hide Outline", comment: "Mac editor heal: stop drawing this spot's circle (it still heals)"))
                .accessibilityLabel(hidden ? String(localized: "Show Outline", comment: "Mac editor heal: draw this spot's circle again")
                                           : String(localized: "Hide Outline", comment: "Mac editor heal: stop drawing this spot's circle (it still heals)"))
                .accessibilityIdentifier("editor.heal.eye")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(isOn ? MacTheme.Editor.rowSelected : Color.clear, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor.heal.row")
    }

    private func wide(_ title: String, _ image: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: View

    private var view: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("view", String(localized: "View", comment: "Mac editor heal: a group"))
            if open.contains("view") { viewRows }
        }
        .padding(.bottom, open.contains("view") ? 10 : 0)
    }

    @ViewBuilder
    private var viewRows: some View {
            Toggle(String(localized: "Visualize Spots", comment: "Mac editor heal: the edge map that shows dust"), isOn: $model.visualizesSpots)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .tint(MacTheme.Editor.accent)
                .padding(.horizontal, 16)
                .frame(height: 26)
                .accessibilityIdentifier("editor.heal.visualize")
            MacEditorValueRow(
                title: String(localized: "Threshold", comment: "Mac editor heal: how sensitive Visualize Spots is"),
                value: model.spotThreshold * 100, range: 0...100, isBipolar: false, resetValue: 50, id: "editor.heal.threshold", model: model,
                change: { value, _ in model.spotThreshold = value / 100 })
                .disabled(!model.visualizesSpots)
                .opacity(model.visualizesSpots ? 1 : 0.45)
            Toggle(String(localized: "Show Spot Pins", comment: "Mac editor heal: draw every spot, not only the picked one"), isOn: $model.showsSpotPins)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .tint(MacTheme.Editor.accent)
                .padding(.horizontal, 16)
                .frame(height: 26)
                .accessibilityIdentifier("editor.heal.pins")
    }
}

/// A list row's picture: the photo around the spot.
private struct MacHealThumbnail: View {
    let image: CGImage?
    let center: NormalizedPoint
    let radius: Double

    var body: some View {
        if let crop = cropped() {
            Image(decorative: crop, scale: 1).resizable().scaledToFill()
        } else {
            MacTheme.Editor.control
        }
    }

    private func cropped() -> CGImage? {
        guard let image else { return nil }
        let short = Double(min(image.width, image.height))
        let side = max(16, radius * short * 4)
        let rect = CGRect(x: center.x * Double(image.width) - side * 0.775, y: center.y * Double(image.height) - side / 2,
                          width: side * 1.55, height: side)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return rect.isEmpty ? nil : image.cropping(to: rect)
    }
}
