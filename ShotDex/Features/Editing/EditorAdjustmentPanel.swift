import SwiftUI
import UIKit

/// The scrolling slider stack shared by global Adjust and the single-mask editor.
/// The group titles are sticky headers inside the scroll — there is no segmented
/// control above them, so the panel spends none of its fixed height on chrome and
/// `Auto` / `Reset` always travel with the group they belong to.
struct EditorAdjustmentGroupsView<Footer: View>: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let groups: [EditorAdjustmentGroup]
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.kinds, id: \.self) { kind in
                            row(for: kind)
                        }
                        .padding(.bottom, 2)
                    } header: {
                        EditorGroupHeader(
                            title: group.title,
                            isFirst: group.id == groups.first?.id,
                            onAuto: group.hasAuto ? { controller.applyAutoTone() } : nil,
                            onReset: { controller.resetAdjustments(group.kinds) }
                        )
                    }
                }
                footer()
                Color.clear.frame(height: 20)
            }
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

    @ViewBuilder
    private func row(for kind: PhotoAdjustmentKind) -> some View {
        if EditorAdjustmentCatalog.format(of: kind) == .toggle {
            EditorToggleRow(
                title: EditorAdjustmentCatalog.shortTitle(of: kind),
                isOn: controller.adjustmentValue(kind) >= 0.5
            ) { isOn in
                controller.setAdjustment(kind, value: isOn ? 1 : 0)
            }
        } else {
            EditorSliderRow(
                kind: kind,
                value: controller.adjustmentValue(kind),
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
        }
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
        groups: [EditorAdjustmentGroup]
    ) {
        self.init(
            controller: controller,
            chrome: chrome,
            groups: groups,
            footer: { EmptyView() }
        )
    }
}

struct EditorGroupHeader: View {
    let title: String
    var isFirst = false
    var onAuto: (() -> Void)?
    var onReset: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer(minLength: 0)
            if let onAuto {
                Button("Auto", action: onAuto)
                    .buttonStyle(EditorTextButtonStyle())
            }
            if let onReset {
                Button("Reset", action: onReset)
                    .buttonStyle(EditorTextButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(isFirst ? EditorTheme.panel : EditorTheme.stickyHeader)
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

    var body: some View {
        Toggle(
            title,
            isOn: Binding(get: { isOn }, set: onChange)
        )
        .font(EditorTheme.rowLabel)
        .tint(EditorTheme.accent)
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}

struct EditorTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(EditorTheme.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}
