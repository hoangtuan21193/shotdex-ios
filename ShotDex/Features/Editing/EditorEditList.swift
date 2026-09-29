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
/// is remembered for the session (`chrome.editListGroup`, `editListOffset`).
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
            rememberedOffset: $chrome.editListOffset,
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
            rememberedOffset: $chrome.transformListOffset,
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
/// top. Where the list was is written to `remembered`, and the exact offset
/// to `rememberedOffset` when the list goes away.
struct EditorSectionList<Section: Hashable>: View {
    let sections: [Section]
    let title: (Section) -> String
    /// What VoiceOver calls the index: "Light, Edit groups".
    let indexName: String
    @Binding var remembered: Section?
    /// The offset the list had when it disappeared; restored when it comes
    /// back to the same section. `scrollPosition(id:)` alone lands on the
    /// section's label, a screen away from where a long group was left.
    @Binding var rememberedOffset: EditorListOffset?
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
    @State private var scrollView = EditorScrollViewHandle()

    static var labelHeight: CGFloat { 26 }
    private static var viewport: String { "EditorSectionList.viewport" }

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
                .background(EditorScrollViewFinder(handle: scrollView))
            }
            .scrollPosition(id: $top, anchor: .top)
            .coordinateSpace(.named(Self.viewport))
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
        .task { await restoreOffset() }
        .onDisappear {
            // Where the user's own scrolling left it. Not read here from the
            // live frames: by the time the list goes, SwiftUI has already
            // snapped it back onto the section label (measured: 0.1pt).
            rememberedOffset = scrollView.userPosition
        }
        .onChange(of: top) { _, section in
            guard let section else { return }
            remembered = section
            onTopChange(section)
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            scrollView.forgetUserPosition()
            withAnimation(EditorTheme.animation) { top = request }
            scrollRequest = nil
        }
    }

    private var current: Section? { top ?? remembered ?? sections.first }

    /// An offset taken at another section (a chip moved the list while it was
    /// away) is not restored: the section wins.
    private var restorableOffset: CGFloat? {
        guard let saved = rememberedOffset, let remembered, saved.section == AnyHashable(remembered) else { return nil }
        return saved.y
    }

    /// `top` brings the remembered section's label to the top; once it sits
    /// there, scroll on by how far past it the list was left — once. The
    /// hosting scroll view is found a frame or two after the first layout,
    /// hence the polling. A label that is not at the top edge is left alone:
    /// once it scrolls away it stops reporting, so correcting against it
    /// again and again ran the list thousands of points off.
    private func restoreOffset() async {
        guard let delta = restorableOffset, delta > 0.5, let section = remembered else { return }
        let key = AnyHashable(section)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            guard let view = scrollView.scrollView, let labelTop = scrollView.sectionTops[key], abs(labelTop) <= 1 else { continue }
            let maxOffset = max(-view.adjustedContentInset.top, view.contentSize.height + view.adjustedContentInset.bottom - view.bounds.height)
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: min(view.contentOffset.y + delta, maxOffset)), animated: false)
            return
        }
    }

    @ViewBuilder
    private func sectionView(_ section: Section) -> some View {
        VStack(spacing: 0) {
            label(section)
                // Kept in a plain reference, not state: it changes every
                // frame of a scroll and nothing draws from it.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.viewport)).minY } action: { [scrollView] minY in
                    scrollView.labelMoved(AnyHashable(section), to: minY)
                }
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
                        scrollView.forgetUserPosition()
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

/// Where a section list was left: the section at its top, and how far past
/// that section's label it was scrolled.
struct EditorListOffset {
    let section: AnyHashable
    let y: CGFloat
}

/// The `UIScrollView` under a SwiftUI `ScrollView`, found from inside its
/// content — iOS 17 has no API to read or set a SwiftUI scroll offset.
@MainActor
final class EditorScrollViewHandle {
    weak var scrollView: UIScrollView?
    /// Each laid-out section label's top, in the scroll view's own frame:
    /// 0 is the top edge, negative is scrolled past.
    var sectionTops: [AnyHashable: CGFloat] = [:]
    /// The last place a finger left the list: the section whose label is at
    /// or above the top edge, and how far past it. Programmatic scrolls (the
    /// index, a chip, the restore itself) do not move it.
    private(set) var userPosition: EditorListOffset?

    /// A jump lands on a section's label; what a finger did before it is
    /// no longer where the list is.
    func forgetUserPosition() {
        userPosition = nil
    }

    func labelMoved(_ section: AnyHashable, to minY: CGFloat) {
        sectionTops[section] = minY
        guard let view = scrollView, view.isTracking || view.isDragging || view.isDecelerating else { return }
        guard let top = sectionTops.filter({ $0.value <= 0.5 }).max(by: { $0.value < $1.value }) else { return }
        userPosition = EditorListOffset(section: top.key, y: -top.value)
    }
}

/// A zero-size view in the list's content that walks up to the scroll view
/// hosting it (the same walk `EditorSliderRow` uses to pause scrolling).
struct EditorScrollViewFinder: UIViewRepresentable {
    let handle: EditorScrollViewHandle

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var candidate = view.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    handle.scrollView = scrollView
                    return
                }
                candidate = current.superview
            }
        }
    }
}
