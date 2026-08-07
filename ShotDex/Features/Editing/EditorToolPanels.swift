import SwiftUI
import UIKit

/// Presets tab (28c): a category strip, an Amount row while a look is active, and
/// a vertical list of preset rows — each a small thumbnail of the photo through
/// that look plus its name, in place of the old swatch grid. One row language with
/// the rest of the panel.
struct EditorFiltersPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            categoryStrip
                .padding(.top, 8)
                .padding(.bottom, 6)

            if controller.recipe.filter != .original {
                amountRow
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }

            presetList
        }
        .frame(maxWidth: .infinity)
        .task { controller.refreshFilterThumbnails() }
    }

    private var amountRow: some View {
        EditorPlainSliderRow(
            title: "Amount",
            value: controller.recipe.filterIntensity,
            range: 0...1,
            isBipolar: false,
            valueText: "\(Int((controller.recipe.filterIntensity * 100).rounded()))%",
            isActive: false,
            detent: 1,
            onBeginDrag: { controller.beginContinuousChange() },
            onDrag: { controller.setFilterIntensity($0) },
            onEndDrag: { controller.endContinuousChange() },
            onReset: { controller.setFilterIntensity(1) }
        )
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(FilmLookCategory.allCases) { category in
                    Button(category.displayName) {
                        controller.chooseFilterCategory(category)
                    }
                    .buttonStyle(
                        EditorChipButtonStyle(
                            isSelected: controller.selectedFilterCategory == category
                        )
                    )
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private var presetList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 3) {
                ForEach(PhotoFilter.all(in: controller.selectedFilterCategory)) { filter in
                    filterRow(filter)
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func filterRow(_ filter: PhotoFilter) -> some View {
        let isSelected = controller.recipe.filter == filter
        return Button {
            controller.chooseFilter(filter)
        } label: {
            HStack(spacing: 10) {
                thumbnail(filter)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isSelected ? EditorTheme.accent : .white.opacity(0.10),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }

                Text(filter.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? EditorTheme.accent : .white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                isSelected ? EditorTheme.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func thumbnail(_ filter: PhotoFilter) -> some View {
        if let image = controller.filterThumbnails[filter] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: swatchColors(for: filter),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Stand-in until the photo's own swatch has rendered: the look applied to a lit
    /// warm tone and a shadowed cool one. Made of the same maths as the real thing,
    /// so the placeholder already leans the way the look does.
    private func swatchColors(for filter: PhotoFilter) -> [Color] {
        guard let look = FilmLookLibrary.look(for: filter) else {
            return legacyColors(for: filter)
        }
        let highlight = look.apply(to: SIMD3(0.82, 0.76, 0.66))
        let shadow = look.apply(to: SIMD3(0.22, 0.25, 0.32))
        return [
            Color(red: highlight.x, green: highlight.y, blue: highlight.z),
            Color(red: shadow.x, green: shadow.y, blue: shadow.z),
        ]
    }

    /// The ten original presets are Core Image chains rather than `FilmLook`s, so
    /// their placeholders stay hand-picked.
    private func legacyColors(for filter: PhotoFilter) -> [Color] {
        switch filter {
        case .vivid: [.pink, .blue]
        case .vividWarm: [.orange, .pink]
        case .vividCool: [.cyan, .indigo]
        case .dramatic: [.black, .orange]
        case .dramaticWarm: [.brown, .orange]
        case .dramaticCool: [.black, .blue]
        case .mono: [.white, .gray]
        case .silvertone: [.gray.opacity(0.5), .white]
        case .noir: [.black, .white]
        default: [.gray, .white.opacity(0.6)]
        }
    }
}

/// Crop tab: straighten, ratio chips, rotate and flip. Mask overlays stay hidden
/// while framing, which the render path already handles.
///
/// The two exits — `Reset Crop` and `Done` — are not here: they take over the
/// panel's action row while this tab is up, so framing controls sit where the
/// session controls normally are instead of adding a second row of buttons.
struct EditorCropPanel: View {
    @Bindable var controller: PhotoEditorController

    var body: some View {
        // Rotate / flip / Reset / Done now live in the panel's action bar (28c), so
        // the crop panel is just the straighten row and the ratio strip.
        VStack(alignment: .leading, spacing: 12) {
            EditorPlainSliderRow(
                title: "Straighten",
                value: controller.recipe.crop.straightenDegrees,
                range: -45...45,
                isBipolar: true,
                valueText: String(
                    format: "%.1f°",
                    controller.recipe.crop.straightenDegrees
                ),
                isActive: false,
                detent: 0,
                onBeginDrag: { controller.beginContinuousChange() },
                onDrag: { controller.setStraighten($0) },
                onEndDrag: { controller.endContinuousChange() },
                onReset: { controller.setStraighten(0) }
            )

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CropAspect.allCases) { aspect in
                        Button(aspect.displayName) {
                            controller.chooseCropAspect(aspect, imageAspect: nil)
                        }
                        .buttonStyle(
                            EditorChipButtonStyle(
                                isSelected: controller.recipe.crop.aspect == aspect
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            Text("Framing stays a draft until you tap Done. Leaving this tab keeps the photo uncropped.")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Slider row for values that are not `PhotoAdjustmentKind` (filter intensity,
/// straighten, mask shape parameters). Uses the same pan arbitration as the
/// adjustment rows.
struct EditorPlainSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let isBipolar: Bool
    let valueText: String
    let isActive: Bool
    /// Value the knob snaps onto while passing it, if this slider has a natural
    /// resting point (0° straighten, 100% filter intensity).
    var detent: Double?
    /// Full-width trough gradient (color mixer / grading rows). When set, the
    /// gradient carries the meaning and the accent progress fill is suppressed —
    /// the knob alone shows the value, mirroring `EditorSliderRow`'s trough
    /// gradients for warmth/tint.
    var trackGradient: LinearGradient?
    let onBeginDrag: () -> Void
    let onDrag: (Double) -> Void
    let onEndDrag: () -> Void
    let onReset: () -> Void

    @State private var dragStartValue = 0.0
    @State private var isHoldingDetent = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.sliderLabelWidth, alignment: .leading)
                .frame(height: EditorLayoutMetrics.sliderRowTotalHeight)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onReset()
                }

            GeometryReader { proxy in
                let width = proxy.size.width
                let position = fraction
                ZStack(alignment: .leading) {
                    if let trackGradient {
                        Capsule()
                            .fill(trackGradient)
                            .frame(height: 4)
                    } else {
                        Capsule()
                            .fill(EditorTheme.sliderTrack)
                            .frame(height: 3)
                    }
                    if isBipolar {
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 1, height: 8)
                            .offset(x: width / 2 - 0.5)
                        if trackGradient == nil {
                            Capsule()
                                .fill(EditorTheme.accent)
                                .frame(width: abs(position - 0.5) * width, height: 3)
                                .offset(x: min(position, 0.5) * width)
                        }
                    } else if trackGradient == nil {
                        Capsule()
                            .fill(EditorTheme.accent)
                            .frame(width: position * width, height: 3)
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: isActive ? 20 : 16, height: isActive ? 20 : 16)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        .offset(x: min(width - 16, max(0, position * width - 8)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .overlay {
                    SliderPanCatcher(
                        onBegan: {
                            dragStartValue = value
                            isHoldingDetent = detent.map { abs(value - $0) < 0.0001 } ?? false
                            onBeginDrag()
                        },
                        onChanged: { translation in
                            guard width > 0,
                                  abs(translation) >= EditorLayoutMetrics.sliderActivationDistance
                            else { return }
                            let span = range.upperBound - range.lowerBound
                            let proposed = dragStartValue
                                + Double(translation / width) * span
                            onDrag(
                                detented(
                                    min(range.upperBound, max(range.lowerBound, proposed)),
                                    trackWidth: width
                                )
                            )
                        },
                        onEnded: { _ in onEndDrag() }
                    )
                }
            }
            .frame(height: EditorLayoutMetrics.sliderRowTotalHeight)

            Text(valueText)
                .font(EditorTheme.rowValue)
                .foregroundStyle(EditorTheme.accent)
                .lineLimit(1)
                .frame(width: EditorLayoutMetrics.sliderValueWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    private func detented(_ value: Double, trackWidth: CGFloat) -> Double {
        guard let detent else { return value }
        let result = EditorLayoutMetrics.snapped(
            value,
            detent: detent,
            range: range,
            trackWidth: trackWidth
        )
        let isOnDetent = result == detent
        if isOnDetent, !isHoldingDetent {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        isHoldingDetent = isOnDetent
        return result
    }
}

struct EditorChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isSelected
                    ? EditorTheme.accent
                    : EditorTheme.control.opacity(configuration.isPressed ? 0.6 : 1),
                in: Capsule()
            )
    }
}
