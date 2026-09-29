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
/// list, each opened by its uppercase label (FS-03.13b §1). Where the list was
/// is remembered for the session (`chrome.editListGroup`).
struct EditorEditList: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    /// A group's controls, laid out to their natural height.
    let content: (EditorGroup) -> AnyView
    /// The group's strip (band, region, point), under its label; nil when none.
    let strip: (EditorGroup) -> AnyView?
    /// The top group changed by scrolling — the tool follows.
    let onTopGroupChange: (EditorGroup) -> Void

    var body: some View {
        EditorSectionList(
            sections: EditorEditIndex.groups,
            title: { EditorEditIndex.title(of: $0, blackAndWhite: controller.isBlackAndWhite) },
            indexName: "Edit groups",
            remembered: $chrome.editListGroup,
            scrollRequest: $chrome.editListScrollRequest,
            initial: chrome.selectedGroup,
            isScrollDisabled: chrome.activePlainSliderID != nil || chrome.activeSlider != nil,
            content: content,
            strip: strip,
            onTopChange: onTopGroupChange
        )
    }
}

/// Transform on the phone: CROP · STRAIGHTEN · UPRIGHT · GEOMETRY in the same
/// list, with the same sticky label and index (FS-03.13b §3).
struct EditorTransformList: View {
    @Bindable var chrome: EditorChromeModel
    let content: (EditorTransformSection) -> AnyView

    var body: some View {
        EditorSectionList(
            sections: EditorTransformSection.shown,
            title: \.title,
            indexName: "Transform groups",
            remembered: $chrome.transformListSection,
            scrollRequest: $chrome.transformListScrollRequest,
            initial: .crop,
            isScrollDisabled: chrome.activePlainSliderID != nil || chrome.activeSlider != nil,
            content: content,
            strip: { _ in nil },
            onTopChange: { _ in }
        )
    }
}

/// One vertical list of labelled sections (FS-03.13b §1, §3). The label of
/// the section at the top of the scroll sticks there as "LIGHT ▼"; a tap on it
/// opens the index, a tap on an index row scrolls that section's label to the
/// top. Where the list was is written to `remembered`.
struct EditorSectionList<Section: Hashable>: View {
    let sections: [Section]
    let title: (Section) -> String
    /// What VoiceOver calls the index: "Light, Edit groups".
    let indexName: String
    @Binding var remembered: Section?
    /// A section the list should scroll to; cleared once it has.
    @Binding var scrollRequest: Section?
    /// Where a list never opened before starts.
    let initial: Section
    let isScrollDisabled: Bool
    let content: (Section) -> AnyView
    let strip: (Section) -> AnyView?
    let onTopChange: (Section) -> Void

    @State private var top: Section?
    @State private var isIndexOpen = false

    static var labelHeight: CGFloat { 26 }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(sections, id: \.self) { section in
                        sectionView(section).id(section)
                    }
                    Color.clear.frame(height: 40)
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $top, anchor: .top)
            .scrollDisabled(isScrollDisabled)
            .environment(\.editorPanelScrolls, false)

            stickyLabel
            if isIndexOpen {
                index
            }
        }
        .onAppear {
            // Back where the list was, or where it starts.
            top = remembered ?? (sections.contains(initial) ? initial : sections.first)
        }
        .onChange(of: top) { _, section in
            guard let section else { return }
            remembered = section
            onTopChange(section)
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            withAnimation(EditorTheme.animation) { top = request }
            scrollRequest = nil
        }
    }

    private var current: Section? { top ?? remembered ?? sections.first }

    @ViewBuilder
    private func sectionView(_ section: Section) -> some View {
        VStack(spacing: 0) {
            label(section)
            if let strip = strip(section) {
                strip.frame(height: EditorLayoutMetrics.editorTargetStripHeight)
            }
            content(section)
        }
    }

    private func label(_ section: Section) -> some View {
        HStack {
            Text(title(section).uppercased())
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: Self.labelHeight)
        .accessibilityAddTraits(.isHeader)
    }

    /// The label of the section at the top, pinned, with a hairline; a tap
    /// opens the index.
    private var stickyLabel: some View {
        let name = current.map(title) ?? ""
        return Button {
            withAnimation(EditorTheme.animation) { isIndexOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(name.uppercased())
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
        .accessibilityLabel("\(name), \(indexName)")
        .accessibilityHint("Shows every group to jump to")
    }

    /// Every section, one row each; a tap scrolls to it and closes.
    private var index: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(sections, id: \.self) { section in
                    Button {
                        top = section
                        withAnimation(EditorTheme.animation) { isIndexOpen = false }
                    } label: {
                        HStack {
                            Text(title(section))
                                .font(EditorTheme.rowLabel)
                                .foregroundStyle(section == current ? Color.white : EditorTheme.secondaryText)
                            Spacer(minLength: 0)
                            if section == current {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(EditorTheme.accent)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(height: EditorLayoutMetrics.editorPanelRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == current ? .isSelected : [])
                }
            }
        }
        .background(EditorTheme.panelSolid)
        .padding(.top, Self.labelHeight)
        .transition(.opacity)
    }
}
