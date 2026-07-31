import SwiftUI
import UIKit

/// Filters tab: preset strip plus an Intensity slider, so a look can be dialled
/// back instead of only being on or off.
struct EditorFiltersPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.recipe.filter.displayName)
                .font(EditorTheme.panelTitle)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(PhotoFilter.allCases) { filter in
                        Button {
                            controller.chooseFilter(filter)
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(gradient(for: filter))
                                    .frame(width: 62, height: 62)
                                    .overlay {
                                        if controller.recipe.filter == filter {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(EditorTheme.accent, lineWidth: 2)
                                        }
                                    }
                                Text(filter.displayName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        controller.recipe.filter == filter
                                            ? EditorTheme.accent
                                            : EditorTheme.secondaryText
                                    )
                                    .lineLimit(1)
                            }
                            .frame(width: 74)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            if controller.recipe.filter != .original {
                EditorPlainSliderRow(
                    title: "Intensity",
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gradient(for filter: PhotoFilter) -> LinearGradient {
        let colors: [Color] = switch filter {
        case .original: [.gray, .white.opacity(0.6)]
        case .vivid: [.pink, .blue]
        case .vividWarm: [.orange, .pink]
        case .vividCool: [.cyan, .indigo]
        case .dramatic: [.black, .orange]
        case .dramaticWarm: [.brown, .orange]
        case .dramaticCool: [.black, .blue]
        case .mono: [.white, .gray]
        case .silvertone: [.gray.opacity(0.5), .white]
        case .noir: [.black, .white]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Crop")
                    .font(EditorTheme.panelTitle)
                Spacer(minLength: 0)
                Button {
                    controller.rotate()
                } label: {
                    Image(systemName: "rotate.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Rotate 90 degrees")

                Button {
                    controller.flip()
                } label: {
                    Image(
                        systemName:
                            "arrow.left.and.right.righttriangle.left.righttriangle.right"
                    )
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Flip horizontally")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 12)

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

            Text("Framing applies as you drag it. Tap Save when the whole edit is ready.")
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
                .frame(height: 44)
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
            .frame(height: 44)

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
