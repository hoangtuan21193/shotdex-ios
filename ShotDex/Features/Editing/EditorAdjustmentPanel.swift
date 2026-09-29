import SwiftUI
import UIKit
import ShotDexKit

/// The scrolling slider stack shared by global Adjust and the single-mask editor.
/// There is no segmented control and no per-group Auto / Reset — reset lives in
/// the action bar. A section shows a plain sticky title only when the scroll holds
/// more than one group (Detail + RAW, the mask editor); a single-group 28c tab
/// shows no header, spending none of the panel's fixed height on chrome.
struct EditorAdjustmentGroupsView<Footer: View>: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let groups: [EditorAdjustmentGroup]
    /// Explicit override; `nil` follows `\.editorPanelScrolls`, which the wide
    /// sidebar turns off for every panel at once.
    var isScrollable: Bool?
    @Environment(\.editorPanelScrolls) private var panelScrolls
    @Environment(\.editMaskCurve) private var editMaskCurve
    @ViewBuilder let footer: () -> Footer

    private var scrolls: Bool { isScrollable ?? panelScrolls }

    var body: some View {
        if scrolls {
            scrollingBody
        } else {
            rows
        }
    }

    private var scrollingBody: some View {
        ScrollView(.vertical) {
            rows
        }
        .scrollDisabled(chrome.activeSlider != nil)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [EditorTheme.panel.opacity(0), EditorTheme.panel],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 22)
            .allowsHitTesting(false)
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.kinds, id: \.self) { kind in
                            row(for: kind)
                        }
                    } header: {
                        // No Auto, no Reset anywhere — the action bar carries reset.
                        // A header survives only to label sections when a scroll
                        // holds more than one (Detail + RAW, the mask editor); a
                        // single-group 28c tab shows no header at all.
                        EditorGroupHeader(
                            title: groups.count > 1 ? group.title : "",
                            isFirst: group.id == groups.first?.id
                        )
                    }
                }
            footer()
            Color.clear.frame(height: 20)
        }
    }

    @ViewBuilder
    private func row(for kind: PhotoAdjustmentKind) -> some View {
        if kind == .vignette {
            // Style heads the vignette rows (FS-03.15b §5); mask scope never
            // lists `.vignette`, so this only appears in global Effects.
            EditorVignetteStyleRow(controller: controller)
        }
        if EditorAdjustmentCatalog.format(of: kind) == .toggle {
            EditorToggleRow(
                title: EditorAdjustmentCatalog.shortTitle(of: kind),
                isOn: controller.adjustmentValue(kind) >= 0.5
            ) { isOn in
                controller.setAdjustment(kind, value: isOn ? 1 : 0)
            }
        } else {
            // A dependent row stays in place and goes quiet until its parent has
            // a value: a vignette's midpoint means nothing at vignette 0, and
            // hiding the row would make the group's shape change under the hand.
            let isLive = EditorAdjustmentCatalog.isEnabled(
                kind,
                in: controller.recipe.adjustments,
                vignetteStyle: controller.recipe.vignetteStyle
            ) && controller.isLensStrengthLive(kind)
            EditorSliderRow(
                kind: kind,
                value: controller.adjustmentValue(kind),
                valueText: controller.rawWhiteBalanceText(kind),
                isActive: chrome.activeSlider == kind,
                onBeginDrag: { beginDrag(kind) },
                onDrag: { value in
                    controller.setAdjustment(kind, value: value)
                },
                onEndDrag: { start, end, wasQuick in endDrag(kind, from: start, to: end, wasQuick: wasQuick) },
                onReset: { controller.resetAdjustment(kind) },
                onEditValue: {
                    chrome.numericEntryKind = kind
                    chrome.numericEntryText = EditorAdjustmentCatalog.editableText(
                        controller.adjustmentValue(kind),
                        of: kind
                    )
                }
            )
            .opacity(isLive ? 1 : EditorTheme.rowDisabled)
            .disabled(!isLive)
            .accessibilityHint(isLive ? "" : dependencyHint(for: kind))
        }
        if kind == .brightness, controller.editingMaskAdjustments, let editMaskCurve {
            // After Light, the mask's own curve (FS-03.15d §2).
            EditorMaskCurveRow(controller: controller, open: editMaskCurve.run)
        }
        if kind == .maskHue {
            // After Hue, the mask's Color swatch (FS-03.15d §2) — not a
            // slider, so it is not a catalog kind.
            EditorMaskTintRow(controller: controller)
        }
    }

    /// Why a row cannot be dragged, for the people who cannot see that it is dim.
    private func dependencyHint(for kind: PhotoAdjustmentKind) -> String {
        if !controller.isLensStrengthLive(kind) {
            return "Strength controls need a lens profile"
        }
        if kind == .vignetteHighlights, controller.recipe.vignetteStyle == .paintOverlay {
            return "Not used by Paint Overlay"
        }
        guard let parent = EditorAdjustmentCatalog.parentKind(of: kind) else { return "" }
        return "Needs \(EditorAdjustmentCatalog.shortTitle(of: parent)) above zero"
    }

    private func beginDrag(_ kind: PhotoAdjustmentKind) {
        controller.selectedAdjustment = kind
        controller.beginContinuousChange()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(EditorTheme.animation) {
            chrome.activeSlider = kind
        }
    }

    private func endDrag(
        _ kind: PhotoAdjustmentKind,
        from start: Double,
        to end: Double,
        wasQuick: Bool
    ) {
        controller.endContinuousChange()
        withAnimation(EditorTheme.animation) {
            chrome.activeSlider = nil
        }
        guard wasQuick, abs(end - start) > 0.0001 else { return }
        chrome.presentUndoToast(
            "\(EditorAdjustmentCatalog.shortTitle(of: kind)) "
                + EditorAdjustmentCatalog.displayText(start, of: kind)
                + " → "
                + EditorAdjustmentCatalog.displayText(end, of: kind)
        )
    }
}

extension EditorAdjustmentGroupsView where Footer == EmptyView {
    init(
        controller: PhotoEditorController,
        chrome: EditorChromeModel,
        groups: [EditorAdjustmentGroup],
        isScrollable: Bool? = nil
    ) {
        self.init(
            controller: controller,
            chrome: chrome,
            groups: groups,
            isScrollable: isScrollable,
            footer: { EmptyView() }
        )
    }
}

/// A plain section label. It carries no Auto / Reset — those are gone from every
/// panel (reset lives in the action bar) — so it exists only to name a section
/// when a scroll holds more than one. An empty title collapses it to zero height,
/// which is how a single-group 28c tab shows no header at all.
struct EditorGroupHeader: View {
    let title: String
    var isFirst = false
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    /// On the phone panel a header is one 40pt grid row (FS-03.12), so the rows
    /// under it stay on the grid.
    private var isGridRow: Bool { usesPanelStyle && !isStacked }

    var body: some View {
        if title.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isGridRow ? AppTheme.Spacing.lg : 14)
        .frame(maxWidth: .infinity)
        .frame(height: isGridRow ? EditorLayoutMetrics.editorPanelRowHeight : 36)
        .background(
            isGridRow
                ? EditorTheme.panelSolid
                : (isFirst ? EditorTheme.panel : EditorTheme.stickyHeader)
        )
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if !isFirst {
                Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
            }
        }
        // A pinned header keeps its slot in the `LazyVStack`'s draw order, which
        // is *below* the rows that come after it — so it stays put but the rows
        // scroll over the top of it, and an opaque slider track passing across it
        // reads as the header having scrolled away. It has to be lifted out of
        // that order to be the thing rows disappear behind.
        .zIndex(1)
    }
}

/// Lens Correction is on/off, not a range, so it gets a switch row rather than a
/// track that only has two useful positions.
struct EditorToggleRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle
    @Environment(\.editorSliderStacked) private var isStacked

    var body: some View {
        if usesPanelStyle {
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
                Text(title)
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelText)
            }
            .toggleStyle(EditorSwitchToggleStyle())
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: isStacked ? EditorLayoutMetrics.sidebarSliderHitHeight : EditorLayoutMetrics.editorPanelRowHeight)
        } else {
            Toggle(
                title,
                isOn: Binding(get: { isOn }, set: onChange)
            )
            .font(EditorTheme.rowLabel)
            .tint(EditorTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: EditorLayoutMetrics.sliderRowTotalHeight)
        }
    }
}

/// The photo editor's switch (FS-03.12): on is a solid white track with a dark
/// knob, off a faint track with a white knob — "on" reads without accent. The
/// whole row toggles, so the target is the row, not the 44×26 switch.
struct EditorSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(EditorTheme.animation) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.white : EditorTheme.sliderNeutralTrack)
                        .frame(width: 44, height: 26)
                    Circle()
                        .fill(configuration.isOn ? EditorTheme.panelSolid : Color.white)
                        .frame(width: 22, height: 22)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A text-only action in a panel row ("Choose Lens", "Delete Point"). White inside
/// the photo editor (accent is Save's alone, FS-03.12); accent in the other tools.
struct EditorTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EditorTextButtonBody(configuration: configuration)
    }
}

private struct EditorTextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.editorUsesPanelStyle) private var usesPanelStyle

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                (usesPanelStyle ? Color.white : EditorTheme.accent)
                    .opacity(configuration.isPressed ? 0.6 : 1)
            )
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Effects › Vignette › Style: Highlight Priority · Color Priority · Paint
/// Overlay, as the shared editor chips. Scrolls sideways rather than
/// truncating when the three names do not fit the width.
struct EditorVignetteStyleRow: View {
    @Bindable var controller: PhotoEditorController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(PhotoVignetteStyle.allCases) { style in
                    Button(style.displayName) {
                        controller.setVignetteStyle(style)
                    }
                    .buttonStyle(EditorChipButtonStyle(isSelected: controller.recipe.vignetteStyle == style))
                    .accessibilityAddTraits(controller.recipe.vignetteStyle == style ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vignette Style")
    }
}

/// A mask's Color: the current tint as a swatch; tapping it opens the
/// grading wheel the overlay colour control uses — hue round, saturation out.
struct EditorMaskTintRow: View {
    @Bindable var controller: PhotoEditorController
    @State private var showsWheel = false

    var body: some View {
        let tint = controller.selectedMaskTint
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("Color")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelText)
                Spacer(minLength: 0)
                Button {
                    withAnimation(EditorTheme.animation) { showsWheel.toggle() }
                } label: {
                    Circle()
                        .fill(tint.map { Color(hue: $0.hue, saturation: $0.saturation, brightness: 1) } ?? Color.clear)
                        .overlay(Circle().stroke(EditorTheme.trackBorder, lineWidth: 1))
                        .overlay {
                            if tint == nil {
                                Image(systemName: "circle.slash").font(.system(size: 13)).foregroundStyle(EditorTheme.dimText)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mask color")
                .accessibilityValue(tint == nil ? "None" : "Hue \(Int((tint!.hue * 360).rounded()))°, \(Int((tint!.saturation * 100).rounded()))%")
            }
            if showsWheel {
                EditorColorWheel(
                    hue: tint?.hue ?? 0,
                    saturation: tint?.saturation ?? 0,
                    diameter: 140,
                    onBegin: { controller.beginContinuousChange() },
                    onChange: { hue, saturation in
                        controller.setSelectedMaskTint(PhotoMaskTint(hue: hue, saturation: saturation))
                    },
                    onEnd: { controller.endContinuousChange() },
                    onReset: { controller.setSelectedMaskTint(nil) }
                )
                .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: EditorLayoutMetrics.editorPanelRowHeight)
    }
}

extension EnvironmentValues {
    /// Opens the curve editor on the picked mask's own curve; set by the
    /// editor screen around the mask panel.
    @Entry var editMaskCurve: EditMaskCurveAction? = nil
}

/// The action behind a mask's Edit Curve, wrapped so the environment holds
/// a value rather than a bare closure.
struct EditMaskCurveAction: Equatable {
    let run: () -> Void

    func callAsFunction() { run() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// "Edit Curve" in a mask's list: opens the curve editor on this mask's own
/// curve, and says whether it has one.
struct EditorMaskCurveRow: View {
    @Bindable var controller: PhotoEditorController
    let open: () -> Void

    private var hasCurve: Bool {
        guard let id = controller.selectedMaskID else { return false }
        return controller.recipe.masks.first { $0.id == id }?.curve != nil
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text("Curve")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.panelText)
                Spacer(minLength: 0)
                Text(hasCurve ? "Edited" : "Edit Curve")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.dimText)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: EditorLayoutMetrics.editorPanelRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit this mask's curve")
    }
}
