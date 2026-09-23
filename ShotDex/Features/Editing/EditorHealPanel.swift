import SwiftUI
import ShotDexKit

/// The Heal tool's panel: Heal or Clone, the size and softness of the next
/// spot (or of the picked one), and a way to delete it. The spots themselves
/// are made and moved on the photo (`EditorHealGuideOverlay`).
struct EditorHealPanel: View {
    @Bindable var controller: PhotoEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hintText)
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            HStack(spacing: 8) {
                ForEach(PhotoHealingMode.allCases) { mode in
                    Button {
                        controller.setHealingMode(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode == .heal ? "bandage" : "square.on.square")
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: controller.healingMode == mode))
                    .accessibilityAddTraits(controller.healingMode == mode ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)

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

            if let spot = controller.selectedHealingSpot,
               let index = controller.recipe.healing.firstIndex(where: { $0.id == spot.id }) {
                HStack {
                    Text("Spot \(index + 1) of \(controller.recipe.healing.count)")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                    Spacer(minLength: 8)
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
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hintText: String {
        if controller.recipe.healing.isEmpty {
            return "Tap a spot on the photo to remove it. ShotDex fills it from beside it."
        }
        return "Drag the dashed circle to fill from somewhere else. Tap the photo for another spot."
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

    private struct DragAnchor {
        var spotID: UUID
        var point: NormalizedPoint
        var touch: CGPoint
    }

    private static let space = "healGuides"

    var body: some View {
        ZStack {
            // Bottom-most: a tap on empty photo makes a spot. Spots above it win
            // taps that land on them.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
                .onTapGesture { location in
                    guard imageRect.width > 0, imageRect.height > 0 else { return }
                    controller.addHealingSpot(at: NormalizedPoint(
                        x: min(1, max(0, location.x / imageRect.width)),
                        y: min(1, max(0, location.y / imageRect.height))
                    ))
                }
                .accessibilityLabel("Photo")
                .accessibilityHint("Tap to add a healing spot")

            ForEach(Array(controller.recipe.healing.enumerated()), id: \.element.id) { index, spot in
                spotGuide(spot, number: index + 1)
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
