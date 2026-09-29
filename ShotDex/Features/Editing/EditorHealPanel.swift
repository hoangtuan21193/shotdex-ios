import SwiftUI
import ShotDexKit

/// The Heal tool's panel: Heal or Clone, the size, softness and strength of the next
/// spot (or of the picked one), and a way to delete it. The spots themselves
/// are made and moved on the photo (`EditorHealGuideOverlay`).
struct EditorHealPanel: View {
    @Bindable var controller: PhotoEditorController
    /// Off in the wide sidebar, which scrolls every panel at once.
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    var body: some View {
        if usesPanelStyle && !isStacked {
            EditorHealPhoneRows(controller: controller)
        } else if panelScrolls {
            ScrollView(.vertical) { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hintText)
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            // Heal · Clone · Red Eye (FS-03.15c §1). Remove would be first and
            // is not shown while it is out (§6).
            HStack(spacing: 8) {
                ForEach(PhotoHealingMode.allCases) { mode in
                    let isSelected = !controller.isRedEyeMode && controller.healingMode == mode
                    Button {
                        controller.setHealingMode(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode == .heal ? "bandage" : "square.on.square")
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                Button {
                    controller.isRedEyeMode = true
                } label: {
                    Label("Red Eye", systemImage: "eye")
                }
                .buttonStyle(EditorChipButtonStyle(isSelected: controller.isRedEyeMode))
                .accessibilityAddTraits(controller.isRedEyeMode ? .isSelected : [])
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)

            if controller.isRedEyeMode {
                redEyeRows
            } else {
                spotRows
            }
            EditorToggleRow(
                title: "Visualize Spots",
                isOn: controller.isVisualizingSpots
            ) { controller.isVisualizingSpots = $0 }
            EditorToggleRow(
                title: "Show Spot Pins",
                isOn: controller.showsSpotPins
            ) { controller.showsSpotPins = $0 }
            if controller.isVisualizingSpots {
                EditorPlainSliderRow(
                    title: "Threshold",
                    value: controller.spotVisualizeThreshold,
                    range: 0...1,
                    isBipolar: false,
                    valueText: "\(Int((controller.spotVisualizeThreshold * 100).rounded()))",
                    isActive: false,
                    onBeginDrag: {},
                    onDrag: { controller.spotVisualizeThreshold = $0 },
                    onEndDrag: {},
                    onReset: { controller.spotVisualizeThreshold = 0.5 }
                )
            }

            if !controller.isRedEyeMode, let spot = controller.selectedHealingSpot,
               let index = controller.recipe.healing.firstIndex(where: { $0.id == spot.id }) {
                HStack {
                    Text("Spot \(index + 1) of \(controller.recipe.healing.count)")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                    Spacer(minLength: 8)
                    Button {
                        controller.findNewSource()
                    } label: {
                        Label("New Source", systemImage: "arrow.triangle.2.circlepath")
                            .font(EditorTheme.maskSubtitle)
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: false))
                    .accessibilityHint("Fills the spot from the next best place around it")
                    Button(role: .destructive) {
                        controller.deleteSelectedHealingSpot()
                    } label: {
                        Label("Delete Spot", systemImage: "trash")
                            .font(EditorTheme.maskSubtitle)
                            .foregroundStyle(EditorTheme.timelineDestructive)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 14)
            }
            if controller.spotCount > 0 {
                HStack {
                    Button(role: .destructive) {
                        if controller.clearAllNeedsConfirmation {
                            isConfirmingClearAll = true
                        } else {
                            controller.removeAllHealingSpots()
                        }
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(EditorTheme.maskSubtitle)
                            .foregroundStyle(EditorTheme.timelineDestructive)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .confirmationDialog(
                        "Clear all spots?",
                        isPresented: $isConfirmingClearAll,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All Spots", role: .destructive) {
                            controller.removeAllHealingSpots()
                        }
                    } message: {
                        Text("All \(controller.spotCount) spots come off the photo. Undo brings them back.")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var isConfirmingClearAll = false

    @ViewBuilder
    private var spotRows: some View {
            EditorPlainSliderRow(
                title: "Size",
                value: controller.healingRadius,
                range: 0.005...0.15,
                isBipolar: false,
                valueText: "\(Int((controller.healingRadius * 200).rounded()))",
                isActive: false,
                onBeginDrag: { controller.beginContinuousChange() },
                onDrag: { controller.setHealingRadius($0) },
                onEndDrag: { controller.endContinuousChange() },
                onReset: { controller.setHealingRadius(0.03) }
            )
            EditorPlainSliderRow(
                title: "Feather",
                value: controller.healingFeather,
                range: 0...1,
                isBipolar: false,
                valueText: "\(Int((controller.healingFeather * 100).rounded()))",
                isActive: false,
                onBeginDrag: { controller.beginContinuousChange() },
                onDrag: { controller.setHealingFeather($0) },
                onEndDrag: { controller.endContinuousChange() },
                onReset: { controller.setHealingFeather(0.5) }
            )
            EditorPlainSliderRow(
                title: "Opacity",
                value: controller.healingOpacity,
                range: 0...1,
                isBipolar: false,
                valueText: "\(Int((controller.healingOpacity * 100).rounded()))",
                isActive: false,
                onBeginDrag: { controller.beginContinuousChange() },
                onDrag: { controller.setHealingOpacity($0) },
                onEndDrag: { controller.endContinuousChange() },
                onReset: { controller.setHealingOpacity(1) }
            )
    }

    @ViewBuilder
    private var redEyeRows: some View {
        EditorPlainSliderRow(
            title: "Pupil Size",
            value: controller.redEyePupilSize,
            range: 0.05...1,
            isBipolar: false,
            valueText: "\(Int((controller.redEyePupilSize * 100).rounded()))",
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setRedEyePupilSize($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setRedEyePupilSize(0.5) }
        )
        EditorPlainSliderRow(
            title: "Darken",
            value: controller.redEyeDarken,
            range: 0...1,
            isBipolar: false,
            valueText: "\(Int((controller.redEyeDarken * 100).rounded()))",
            isActive: false,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setRedEyeDarken($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setRedEyeDarken(0.5) }
        )
        HStack {
            Button {
                controller.fixRedEyes()
            } label: {
                Label("Fix Red Eye", systemImage: "wand.and.stars")
                    .font(EditorTheme.maskSubtitle)
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: false))
            .accessibilityHint("Finds every red pupil in the photo and fixes it")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        if let eye = controller.selectedRedEye,
           let index = controller.recipe.redEyes.firstIndex(where: { $0.id == eye.id }) {
            HStack {
                Text("Eye \(index + 1) of \(controller.recipe.redEyes.count)")
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    controller.deleteSelectedRedEye()
                } label: {
                    Label("Delete Spot", systemImage: "trash")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.timelineDestructive)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 14)
        }
    }

    private var hintText: String {
        if controller.isRedEyeMode {
            return controller.recipe.redEyes.isEmpty
                ? "Tap a red eye to fix it."
                : "Drag a circle to move it. Tap another eye to fix it too."
        }
        if controller.recipe.healing.isEmpty {
            return "Tap a spot to remove it, or drag along a wire. ShotDex fills it from beside it."
        }
        return "Drag the dashed outline to fill from somewhere else. Tap or drag the photo for another."
    }
}

/// Heal on the phone (FS-03.13c §4), top to bottom: Heal · Clone · Red Eye,
/// the pinned pills, then — scrolling — SELECTED SPOT (New Source · Delete
/// Spot, dimmed with nothing picked) and SPOTS · n (Visualize Spots,
/// Threshold while it is on, Show Spot Pins · Clear All). No Remove (§4).
struct EditorHealPhoneRows: View {
    @Bindable var controller: PhotoEditorController
    @State private var isConfirmingClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            modeRow
            if controller.isRedEyeMode {
                EditorPillRow(pills: redEyePills) { EmptyView() }
            } else {
                EditorPillRow(pills: healPills) { EmptyView() }
            }
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if controller.isRedEyeMode {
                        redEyeRows
                    } else {
                        spotRows
                    }
                }
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var modeRow: some View {
        HStack(spacing: EditorStripLayout.chipSpacing) {
            ForEach(PhotoHealingMode.allCases) { mode in
                modeChip(
                    mode.displayName,
                    systemImage: mode == .heal ? "bandage" : "square.on.square",
                    isSelected: !controller.isRedEyeMode && controller.healingMode == mode
                ) { controller.setHealingMode(mode) }
            }
            modeChip("Red Eye", systemImage: "eye", isSelected: controller.isRedEyeMode) {
                controller.isRedEyeMode = true
            }
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }

    private func modeChip(_ title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            EditorPanelChipLabel(title: title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Pills

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))" }

    private var healPills: [EditorPill] {
        [
            EditorPill(
                id: "size", title: "Size", value: controller.healingRadius, range: 0.005...0.15, defaultValue: 0.03,
                text: { "\(Int(($0 * 200).rounded()))" }, set: { controller.setHealingRadius($0) },
                begin: { controller.beginContinuousChange() }, end: { controller.endContinuousChange() }
            ),
            EditorPill(
                id: "feather", title: "Feather", value: controller.healingFeather, range: 0...1, defaultValue: 0.5,
                text: percent, set: { controller.setHealingFeather($0) },
                begin: { controller.beginContinuousChange() }, end: { controller.endContinuousChange() }
            ),
            EditorPill(
                id: "opacity", title: "Opacity", value: controller.healingOpacity, range: 0...1, defaultValue: 1,
                text: percent, set: { controller.setHealingOpacity($0) },
                begin: { controller.beginContinuousChange() }, end: { controller.endContinuousChange() }
            ),
        ]
    }

    private var redEyePills: [EditorPill] {
        [
            EditorPill(
                id: "pupil", title: "Pupil", value: controller.redEyePupilSize, range: 0.05...1, defaultValue: 0.5,
                text: percent, set: { controller.setRedEyePupilSize($0) },
                begin: { controller.beginContinuousChange() }, end: { controller.endContinuousChange() }
            ),
            EditorPill(
                id: "darken", title: "Darken", value: controller.redEyeDarken, range: 0...1, defaultValue: 0.5,
                text: percent, set: { controller.setRedEyeDarken($0) },
                begin: { controller.beginContinuousChange() }, end: { controller.endContinuousChange() }
            ),
        ]
    }

    // MARK: Sections

    private func label(_ text: String) -> some View {
        Text(text)
            .font(EditorTheme.groupLabel)
            .tracking(1.1)
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: 26)
            .accessibilityAddTraits(.isHeader)
    }

    private func chip(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EditorPanelChipLabel(title: title, systemImage: systemImage)
                .foregroundStyle(isDestructive ? EditorTheme.timelineDestructive : .white)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EditorChipButtonStyle(isSelected: isSelected))
    }

    @ViewBuilder
    private var spotRows: some View {
        let hasSpot = controller.selectedHealingSpot != nil
        label("SELECTED SPOT")
        HStack(spacing: EditorStripLayout.chipSpacing) {
            chip("New Source", systemImage: "arrow.triangle.2.circlepath") { controller.findNewSource() }
                .accessibilityHint("Fills the spot from the next best place around it")
            chip("Delete Spot", systemImage: "trash", isDestructive: true) { controller.deleteSelectedHealingSpot() }
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        .disabled(!hasSpot)
        .opacity(hasSpot ? 1 : EditorTheme.rowDisabled)

        label("SPOTS · \(controller.spotCount)")
        EditorToggleRow(
            title: "Visualize Spots",
            isOn: controller.isVisualizingSpots
        ) { controller.isVisualizingSpots = $0 }
        if controller.isVisualizingSpots {
            EditorPlainSliderRow(
                title: "Threshold",
                value: controller.spotVisualizeThreshold,
                range: 0...1,
                isBipolar: false,
                valueText: percent(controller.spotVisualizeThreshold),
                isActive: false,
                onBeginDrag: {},
                onDrag: { controller.spotVisualizeThreshold = $0 },
                onEndDrag: {},
                onReset: { controller.spotVisualizeThreshold = 0.5 }
            )
        }
        HStack(spacing: EditorStripLayout.chipSpacing) {
            chip("Show Spot Pins", systemImage: "mappin", isSelected: controller.showsSpotPins) {
                controller.showsSpotPins.toggle()
            }
            .accessibilityAddTraits(controller.showsSpotPins ? .isSelected : [])
            chip("Clear All", systemImage: "trash", isDestructive: true) {
                if controller.clearAllNeedsConfirmation {
                    isConfirmingClearAll = true
                } else {
                    controller.removeAllHealingSpots()
                }
            }
            .disabled(controller.spotCount == 0)
            .opacity(controller.spotCount == 0 ? EditorTheme.rowDisabled : 1)
            .confirmationDialog("Clear all spots?", isPresented: $isConfirmingClearAll, titleVisibility: .visible) {
                Button("Clear All Spots", role: .destructive) {
                    controller.removeAllHealingSpots()
                }
            } message: {
                Text("All \(controller.spotCount) spots come off the photo. Undo brings them back.")
            }
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
    }

    @ViewBuilder
    private var redEyeRows: some View {
        HStack(spacing: EditorStripLayout.chipSpacing) {
            chip("Fix Red Eye", systemImage: "wand.and.stars") { controller.fixRedEyes() }
                .accessibilityHint("Finds every red pupil in the photo and fixes it")
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        let hasEye = controller.selectedRedEye != nil
        label("SELECTED SPOT")
        HStack(spacing: EditorStripLayout.chipSpacing) {
            chip("Delete Spot", systemImage: "trash", isDestructive: true) { controller.deleteSelectedRedEye() }
        }
        .padding(.horizontal, EditorStripLayout.horizontalInset)
        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
        .disabled(!hasEye)
        .opacity(hasEye ? 1 : EditorTheme.rowDisabled)
    }
}

/// The spots on the photo: a solid circle where the repair is, a dashed one
/// where it is filled from, a line between. Lives inside the zoomed stack like
/// the mask guides, so strokes and hit targets divide by the zoom.
struct EditorHealGuideOverlay: View {
    @Bindable var controller: PhotoEditorController
    let imageRect: CGRect
    var zoomScale: CGFloat = 1

    @State private var drag: DragAnchor?
    @State private var redEyeDrag: DragAnchor?

    private struct DragAnchor {
        var spotID: UUID
        var point: NormalizedPoint
        var touch: CGPoint
    }

    private static let space = "healGuides"

    var body: some View {
        ZStack {
            // Taps and strokes on empty photo land on the paint layer under
            // this overlay (`EditorImageStage`); spots here win the touches
            // that land on them.
            let pinned = controller.pinnedSpotIDs
            ForEach(Array(controller.recipe.healing.enumerated()), id: \.element.id) { index, spot in
                if pinned.contains(spot.id) { spotGuide(spot, number: index + 1) }
            }
            ForEach(Array(controller.recipe.redEyes.enumerated()), id: \.element.id) { index, eye in
                if pinned.contains(eye.id) { redEyeGuide(eye, number: index + 1) }
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private func point(_ normalized: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imageRect.width * normalized.x,
            y: imageRect.minY + imageRect.height * normalized.y
        )
    }

    @ViewBuilder
    private func spotGuide(_ spot: PhotoHealingSpot, number: Int) -> some View {
        let isSelected = spot.id == controller.selectedHealingSpotID
        let radius = spot.radius * min(imageRect.width, imageRect.height)
        let center = point(spot.center)
        let source = point(spot.source)
        let color: Color = isSelected ? EditorTheme.accent : .white
        let line = (isSelected ? 2 : 1.25) / zoomScale

        // A stroke spot draws its stroke — the repair — and, when picked, the
        // same stroke where it is filled from.
        if let stroke = spot.stroke {
            strokePath(stroke, at: spot.center)
                .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: radius * 2, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
            if isSelected {
                strokePath(stroke, at: spot.source)
                    .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round, dash: [5 / zoomScale, 4 / zoomScale]))
                    .allowsHitTesting(false)
            }
        }

        if isSelected {
            Path { path in
                path.move(to: source)
                path.addLine(to: center)
            }
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1 / zoomScale, dash: [4 / zoomScale, 3 / zoomScale]))
            .allowsHitTesting(false)
        }

        // Where it is filled from — only for the picked spot, so a photo with
        // twenty spots is not a net of dashed circles.
        if isSelected {
            handle(
                at: source,
                radius: radius,
                style: StrokeStyle(lineWidth: line, dash: [5 / zoomScale, 4 / zoomScale]),
                color: color,
                label: "Source for spot \(number)",
                spot: spot,
                moves: \.source
            )
        }

        handle(
            at: center,
            radius: radius,
            style: StrokeStyle(lineWidth: line),
            color: color,
            label: "Healing spot \(number)",
            spot: spot,
            moves: \.center
        )
    }

    /// A Red Eye spot: its circle, accent when picked; drag to move it.
    private func redEyeGuide(_ eye: PhotoRedEyeSpot, number: Int) -> some View {
        let isSelected = eye.id == controller.selectedRedEyeID
        let radius = eye.radius * min(imageRect.width, imageRect.height)
        let hit = max(radius * 2, EditorLayoutMetrics.maskGuideHitTarget / zoomScale)
        let color: Color = isSelected ? EditorTheme.accent : .white
        return Circle()
            .stroke(color, style: StrokeStyle(lineWidth: (isSelected ? 2 : 1.25) / zoomScale, dash: [3 / zoomScale, 2 / zoomScale]))
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: .black.opacity(0.5), radius: 2 / zoomScale)
            .frame(width: hit, height: hit)
            .contentShape(Circle())
            .position(point(eye.center))
            .onTapGesture { controller.selectedRedEyeID = eye.id }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if redEyeDrag == nil {
                            controller.selectedRedEyeID = eye.id
                            redEyeDrag = DragAnchor(spotID: eye.id, point: eye.center, touch: value.startLocation)
                            controller.beginContinuousChange()
                        }
                        guard let redEyeDrag, imageRect.width > 0, imageRect.height > 0 else { return }
                        let moved = NormalizedPoint(
                            x: min(1, max(0, redEyeDrag.point.x + (value.location.x - redEyeDrag.touch.x) / imageRect.width)),
                            y: min(1, max(0, redEyeDrag.point.y + (value.location.y - redEyeDrag.touch.y) / imageRect.height))
                        )
                        controller.updateRedEye(redEyeDrag.spotID) { $0.center = moved }
                    }
                    .onEnded { _ in
                        redEyeDrag = nil
                        controller.endContinuousChange()
                    }
            )
            .accessibilityLabel("Red eye \(number)")
            .accessibilityHint("Drag to move")
    }

    private func strokePath(_ stroke: [NormalizedPoint], at anchor: NormalizedPoint) -> Path {
        Path { path in
            path.addLines(stroke.map { point(NormalizedPoint(x: anchor.x + $0.x, y: anchor.y + $0.y)) })
        }
    }

    private func handle(
        at location: CGPoint,
        radius: CGFloat,
        style: StrokeStyle,
        color: Color,
        label: String,
        spot: PhotoHealingSpot,
        moves keyPath: WritableKeyPath<PhotoHealingSpot, NormalizedPoint>
    ) -> some View {
        // Never smaller than a finger, whatever the spot's size or the zoom.
        let hit = max(radius * 2, EditorLayoutMetrics.maskGuideHitTarget / zoomScale)
        return Circle()
            .stroke(color, style: style)
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: .black.opacity(0.5), radius: 2 / zoomScale)
            .frame(width: hit, height: hit)
            .contentShape(Circle())
            .position(location)
            .onTapGesture { controller.selectHealingSpot(spot.id) }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if drag == nil {
                            controller.selectHealingSpot(spot.id)
                            drag = DragAnchor(spotID: spot.id, point: spot[keyPath: keyPath], touch: value.startLocation)
                            controller.beginContinuousChange()
                        }
                        guard let drag, imageRect.width > 0, imageRect.height > 0 else { return }
                        let moved = NormalizedPoint(
                            x: min(1, max(0, drag.point.x + (value.location.x - drag.touch.x) / imageRect.width)),
                            y: min(1, max(0, drag.point.y + (value.location.y - drag.touch.y) / imageRect.height))
                        )
                        controller.updateHealingSpot(drag.spotID) { $0[keyPath: keyPath] = moved }
                    }
                    .onEnded { _ in
                        drag = nil
                        controller.endContinuousChange()
                    }
            )
            .accessibilityLabel(label)
            .accessibilityHint("Drag to move")
    }
}
