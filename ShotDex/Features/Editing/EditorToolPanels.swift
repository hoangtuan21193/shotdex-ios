import SwiftUI
import UIKit

/// Presets tab (30c): an Amount row while a look is active, then every look at
/// once in one horizontal scroll of thumbnail cards — each a small preview of the
/// photo through that look plus its name. No category picker (Basic / Film / B&W);
/// the strips are flattened into the single scroll.
struct EditorFiltersPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel

    var body: some View {
        VStack(spacing: 0) {
            if controller.recipe.filter != .original {
                amountRow
                    .padding(.top, 8)
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }

            presetStrip
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

    /// Every look at once — no category picker — in one horizontal scroll of
    /// thumbnail cards. Opens scrolled to the active look. Swatches stream in as the
    /// controller renders each category batch; until one arrives the card draws the
    /// look's two-tone gradient stand-in.
    private var presetStrip: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(PhotoFilter.allCases) { filter in
                        filterCard(filter).id(filter)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scroller.scrollTo(controller.recipe.filter, anchor: .center)
            }
        }
    }

    private func filterCard(_ filter: PhotoFilter) -> some View {
        let isSelected = controller.recipe.filter == filter
        return Button {
            controller.chooseFilter(filter)
        } label: {
            VStack(spacing: 5) {
                thumbnail(filter)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? EditorTheme.accent : .white.opacity(0.10),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(EditorTheme.accent)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(4)
                        }
                    }

                Text(filter.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? EditorTheme.accent : EditorTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 66)
            }
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

/// Crop tab: rotate / flip / reset, straighten, ratio chips. Mask overlays stay
/// hidden while framing, which the render path already handles.
///
/// Turn 31: there is no in-panel command row, so the framing actions that lived
/// there — rotate, flip, reset crop — are a button row at the top of this panel
/// (rotate and flip are also in the band's ⋯ menu). There is no Done: the crop
/// commits when the tab is left or the edit is saved.
struct EditorCropPanel: View {
    @Bindable var controller: PhotoEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionRow

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

            Text("The crop applies when you leave this tab or save.")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rotate 90° / Flip / Reset Crop — the framing actions that used to sit in the
    /// panel's command row. Reset is disabled until there is a crop to reset.
    private var actionRow: some View {
        HStack(spacing: 8) {
            cropAction("Rotate", icon: "rotate.right", isEnabled: true) {
                controller.rotate()
            }
            cropAction(
                "Flip",
                icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isEnabled: true
            ) {
                controller.flip()
            }
            cropAction(
                "Reset",
                icon: "crop",
                isEnabled: controller.recipe.crop != .identity
            ) {
                controller.resetCrop()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func cropAction(
        _ title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isEnabled ? .white : EditorTheme.dimText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(EditorTheme.control, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
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

    var body: some View {
        EditorValueSlider(
            label: title,
            value: value,
            range: range,
            valueText: valueText,
            isActive: isActive,
            anchor: isBipolar ? (range.lowerBound + range.upperBound) / 2 : range.lowerBound,
            showsAnchorNotch: isBipolar,
            detent: detent,
            trackGradient: trackGradient,
            onBeginDrag: onBeginDrag,
            onDrag: onDrag,
            onEndDrag: { _, _, _ in onEndDrag() },
            onReset: onReset,
            onEditValue: nil
        )
    }
}

struct EditorChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isSelected
                    ? EditorTheme.accent
                    : EditorTheme.control.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
