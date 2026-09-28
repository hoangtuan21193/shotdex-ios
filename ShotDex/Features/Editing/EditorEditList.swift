import SwiftUI

/// The groups of the phone's Edit list, in the catalog's order (FS-03.13b
/// §1). The index is built from this — a group FS-03.15 adds shows up in it
/// without anyone writing its name twice. Geometry is not here: it belongs
/// to Transform.
enum EditorEditIndex {
    static let groups: [EditorGroup] = [
        .light, .curve, .color, .colorMix, .pointColor, .grade,
        .effects, .lensBlur, .detail, .optics, .calibration,
    ]

    /// What the list, the index and the chip call a group.
    static func title(of group: EditorGroup, blackAndWhite: Bool) -> String {
        group.title(blackAndWhite: blackAndWhite)
    }
}

/// Edit on the phone: every group one after another in **one** vertical
/// list, each opened by its uppercase label (FS-03.13b §1). The label of the
/// group at the top of the scroll sticks there as "LIGHT ▼"; a tap on it opens
/// the index, a tap on an index row scrolls that group's label to the top.
/// Where the list was is remembered for the session (`chrome.editListGroup`).
struct EditorEditList: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    /// A group's controls, laid out to their natural height.
    let content: (EditorGroup) -> AnyView
    /// The group's strip (band, region, point), under its label; nil when none.
    let strip: (EditorGroup) -> AnyView?
    /// The top group changed by scrolling — the wheel and the tool follow.
    let onTopGroupChange: (EditorGroup) -> Void

    @State private var topGroup: EditorGroup?
    @State private var isIndexOpen = false

    static let labelHeight: CGFloat = 26

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(EditorEditIndex.groups, id: \.self) { group in
                        section(group).id(group)
                    }
                    Color.clear.frame(height: 40)
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topGroup, anchor: .top)
            .scrollDisabled(chrome.activePlainSliderID != nil || chrome.activeSlider != nil)
            .environment(\.editorPanelScrolls, false)

            stickyLabel
            if isIndexOpen {
                index
            }
        }
        .onAppear {
            // Back where the list was, or at the chip's group.
            topGroup = chrome.editListGroup ?? chrome.selectedGroup
        }
        .onChange(of: topGroup) { _, group in
            guard let group else { return }
            chrome.editListGroup = group
            onTopGroupChange(group)
        }
        .onChange(of: chrome.editListScrollRequest) { _, request in
            guard let request else { return }
            withAnimation(EditorTheme.animation) { topGroup = request }
            chrome.editListScrollRequest = nil
        }
    }

    private var current: EditorGroup { topGroup ?? chrome.editListGroup ?? .light }

    @ViewBuilder
    private func section(_ group: EditorGroup) -> some View {
        VStack(spacing: 0) {
            label(group)
            if let strip = strip(group) {
                strip.frame(height: EditorLayoutMetrics.editorTargetStripHeight)
            }
            content(group)
        }
    }

    private func label(_ group: EditorGroup) -> some View {
        HStack {
            Text(EditorEditIndex.title(of: group, blackAndWhite: controller.isBlackAndWhite).uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: Self.labelHeight)
        .accessibilityAddTraits(.isHeader)
    }

    /// The label of the group at the top, pinned, with a hairline; a tap opens
    /// the index.
    private var stickyLabel: some View {
        Button {
            withAnimation(EditorTheme.animation) { isIndexOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(EditorEditIndex.title(of: current, blackAndWhite: controller.isBlackAndWhite).uppercased())
                    .font(EditorTheme.groupLabel)
                    .tracking(1.1)
                Image(systemName: isIndexOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: Self.labelHeight)
            .frame(maxWidth: .infinity)
            .background(EditorTheme.panelSolid)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EditorEditIndex.title(of: current, blackAndWhite: controller.isBlackAndWhite)), Edit groups")
        .accessibilityHint("Shows every group to jump to")
    }

    /// Every group, one row each; a tap scrolls to it and closes.
    private var index: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(EditorEditIndex.groups, id: \.self) { group in
                    Button {
                        topGroup = group
                        withAnimation(EditorTheme.animation) { isIndexOpen = false }
                    } label: {
                        HStack {
                            Text(EditorEditIndex.title(of: group, blackAndWhite: controller.isBlackAndWhite))
                                .font(EditorTheme.rowLabel)
                                .foregroundStyle(group == current ? Color.white : EditorTheme.secondaryText)
                            Spacer(minLength: 0)
                            if group == current {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(EditorTheme.accent)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(group == current ? .isSelected : [])
                }
            }
        }
        .background(EditorTheme.panelSolid)
        .padding(.top, Self.labelHeight)
        .transition(.opacity)
    }
}
