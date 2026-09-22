import SwiftUI

/// Which side of the window the editor's tool sidebar sits on.
///
/// A preference, not a layout detail: which hand holds the iPad decides whether
/// the panel is in the way, and Lightroom, Capture One and Photoshop all let the
/// user move it. Default `.trailing`, like Lightroom Classic's develop panels.
enum EditorSidebarEdge: String, CaseIterable, Identifiable {
    case leading
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: "Left"
        case .trailing: "Right"
        }
    }

    /// The glyph for "collapse towards this edge".
    var collapseIcon: String {
        switch self {
        case .leading: "sidebar.leading"
        case .trailing: "sidebar.trailing"
        }
    }

    /// And the glyph for bringing it back — the same sidebar symbol filled in,
    /// so the rail button reads as a toggle rather than two unrelated controls.
    var expandIcon: String {
        switch self {
        case .leading: "sidebar.squares.leading"
        case .trailing: "sidebar.squares.trailing"
        }
    }

    static func resolved(_ rawValue: String) -> EditorSidebarEdge {
        EditorSidebarEdge(rawValue: rawValue) ?? .trailing
    }
}

/// One stop on the wide editor's tool rail — the vertical icon column on the
/// window's outer edge.
///
/// Lightroom's arrangement on an iPad, and taken for its reasons rather than its
/// looks: the five are mutually exclusive, so they are a radio control and not
/// five disclosures; they are the first decision of an edit, so they sit where
/// nothing scrolls them away; and a column costs width — the dimension a
/// landscape canvas has to spare — instead of the panel's height, which is what
/// the parameter list is always short of. `edit` is the whole adjustment stack;
/// the other four each take the photo over.
enum EditorRailMode: String, CaseIterable, Identifiable {
    case edit
    case presets
    case crop
    case mask
    case markup

    var id: String { rawValue }

    /// The group this rail stop puts the editor into. `edit` lands on Light,
    /// which is where an edit starts and what the accordion opens on.
    var group: EditorGroup {
        switch self {
        case .edit: .light
        case .presets: .presets
        case .crop: .cropGeometry
        case .mask: .mask
        case .markup: .markup
        }
    }

    var title: String {
        switch self {
        case .edit: "Edit"
        default: group.wideTitle
        }
    }

    /// Icon-only in the rail, so the glyph carries the whole name. `edit` gets
    /// the sliders that every photo app uses for "adjust".
    var icon: String {
        switch self {
        case .edit: "slider.horizontal.3"
        default: group.icon
        }
    }

    /// Which stop a group belongs to. Everything that is not one of the four
    /// stage tools is part of the adjustment stack.
    static func containing(_ group: EditorGroup) -> EditorRailMode {
        allCases.first { $0 != .edit && $0.group == group } ?? .edit
    }
}

/// The rail itself: five modes at the top, History and the panel toggle at the
/// bottom. It never collapses — with the panel away it is the only thing left
/// that can bring a tool back, which is exactly the job Lightroom's rail does.
struct EditorToolRail: View {
    let selected: EditorRailMode
    /// Marks the modes holding an edit on this photo, the way the section
    /// headers mark theirs.
    let editedModes: Set<EditorRailMode>
    let isPanelHidden: Bool
    /// History is a panel here, not a sheet, so its rail stop is a selectable
    /// mode like the five above it rather than a button that opens something.
    let isHistoryActive: Bool
    let edge: EditorSidebarEdge
    var select: (EditorRailMode) -> Void
    var showHistory: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ForEach(EditorRailMode.allCases) { mode in
                railButton(
                    icon: mode.icon,
                    title: mode.title,
                    // Lit means "this mode's panel is open" — not "this mode is
                    // selected". With the panel folded away nothing is lit, so
                    // the rail never claims to be showing something it is not.
                    isActive: mode == selected && !isHistoryActive && !isPanelHidden,
                    hasEdits: editedModes.contains(mode)
                ) {
                    select(mode)
                }
            }

            Spacer(minLength: AppTheme.Spacing.md)

            railButton(
                icon: "clock.arrow.circlepath",
                title: "History",
                isActive: isHistoryActive,
                hasEdits: false,
                action: showHistory
            )
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(width: EditorLayoutMetrics.sidebarRailWidth)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: edge == .trailing ? .leading : .trailing) {
            Rectangle().fill(EditorTheme.panelDivider).frame(width: 1)
        }
    }

    private func railButton(
        icon: String,
        title: String,
        isActive: Bool,
        hasEdits: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(EditorTheme.commandGlyph)
                .foregroundStyle(isActive ? EditorTheme.accent : EditorTheme.secondaryText)
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .background {
                    if isActive {
                        RoundedRectangle.app(AppTheme.Radius.sm)
                            .fill(Color.white.opacity(0.08))
                    }
                }
                // The dot sits on the glyph rather than beside it: the rail is
                // 48pt wide and has no room for a second column.
                .overlay(alignment: .topTrailing) {
                    if hasEdits {
                        Circle()
                            .fill(EditorTheme.accent)
                            .frame(width: 5, height: 5)
                            .padding(AppTheme.Spacing.sm)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// One collapsible group in the wide-screen sidebar: a header that toggles, and
/// the group's own panel underneath when it is open.
///
/// Lightroom's model, deliberately: every group is listed at once and any number
/// of them can be open, so a light edit and a colour edit are one scroll apart
/// instead of two taps through a picker. The phone keeps the wheel — there the
/// screen only has room for one group anyway.
struct EditorSidebarSection<Content: View>: View {
    @ScaledMetric(relativeTo: .subheadline)
    private var headerHeight = EditorLayoutMetrics.sidebarSectionHeaderHeight
    let group: EditorGroup
    let isExpanded: Bool
    /// True when this is the group the photo's stage is currently in (crop
    /// handles up, mask overlay live). Only one group can hold the stage, so
    /// this is not the same thing as being open.
    let isActive: Bool
    /// This group has been touched on this photo. With a stack of collapsible
    /// sections there is otherwise no way to tell which ones hold an edit
    /// without opening every one of them — the same job Lightroom's per-panel
    /// switch does.
    var hasEdits = false
    /// Gap and inset the card draws with. 6 on a short column, 8 elsewhere —
    /// the caller reads it from the metrics so one column has one answer.
    var spacing: CGFloat = 8
    var toggle: () -> Void
    /// Puts this group — and only this group — back to its defaults. Absent
    /// when the group has nothing to reset, which is also when the button
    /// would be a lie.
    var reset: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    // The disclosure leads the row, the way every desktop
                    // develop panel writes it: the triangle is what the row is
                    // *for*, and reading it before the name is one saccade
                    // rather than a jump to the far margin and back. The group
                    // icon went with the move — the rail carries the icons now,
                    // and a glyph per header made eight rows of decoration.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isActive ? EditorTheme.accent : EditorTheme.dimText)
                        .frame(width: AppTheme.Spacing.md)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    Text(group.title)
                        .font(EditorTheme.sidebarGroupLabel)
                        .foregroundStyle(isActive || isExpanded ? Color.white : EditorTheme.secondaryText)
                    if hasEdits {
                        Circle()
                            .fill(EditorTheme.accent)
                            .frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.leading, AppTheme.Spacing.md)
                .padding(.trailing, hasEdits && reset != nil ? 0 : AppTheme.Spacing.md)
                .frame(height: headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(group.title)
            .accessibilityValue(
                [isExpanded ? "Expanded" : "Collapsed", hasEdits ? "Edited" : nil]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
            .accessibilityAddTraits(isExpanded ? [.isSelected, .isButton] : .isButton)
            .overlay(alignment: .trailing) {
                // Reset belongs to the group it resets, next to the name that
                // says what it will undo — not to a button at the foot of the
                // panel that wipes the whole photo. It only appears once there
                // is something to put back.
                if hasEdits, let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EditorTheme.secondaryText)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .padding(.trailing, AppTheme.Spacing.xs)
                    .accessibilityLabel("Reset \(group.title)")
                }
            }

            if isExpanded {
                content()
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
        // A card, not a slice of one long list: each group reads as its own
        // block the way the histogram above them already does. The hairline
        // between sections went with it — a divider inside a card separates
        // rows that belong together, and between cards the gap does the job.
        .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.lg))
        .padding(.horizontal, spacing)
        .padding(.top, spacing)
    }
}

/// The grab strip on the sidebar's inner edge.
struct EditorSidebarResizeHandle: View {
    let edge: EditorSidebarEdge
    /// Points the sidebar should grow by (negative shrinks), as the finger moves.
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(EditorTheme.panelSolid)
            .overlay {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 3, height: 34)
            }
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                Rectangle().fill(EditorTheme.panelTopHairline).frame(width: 1)
            }
            .frame(width: EditorLayoutMetrics.sidebarResizeHandleWidth)
            // Drawn 10pt so it reads as a seam, grabbed at 24 so a finger can
            // actually find it.
            .contentShape(
                Rectangle()
                    .size(
                        width: EditorLayoutMetrics.sidebarResizeGrabWidth,
                        height: 10_000
                    )
                    .offset(
                        x: -(EditorLayoutMetrics.sidebarResizeGrabWidth
                            - EditorLayoutMetrics.sidebarResizeHandleWidth) / 2,
                        y: -5_000
                    )
            )
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Dragging *away* from the sidebar's own edge widens it,
                        // whichever side it is parked on.
                        let delta = edge == .trailing
                            ? -value.translation.width
                            : value.translation.width
                        onDrag(delta)
                    }
                    .onEnded { _ in onEnd() }
            )
            // Not hidden from assistive technology: the width is a real
            // setting, and a drag is not a route VoiceOver or Switch Control
            // can take — so the handle is an adjustable element, and the
            // action below moves it 40pt at a time.
            //
            // (This comment used to promise "the ⋯ menu carries the same
            // three widths". There is no such menu and never was; the
            // adjustable action is the whole answer.)
            .accessibilityLabel("Tools panel width")
            .accessibilityHint("Adjust to resize the panel")
            .accessibilityAdjustableAction { direction in
                onDrag(direction == .increment ? 40 : -40)
                onEnd()
            }
    }
}

/// Whether a tool panel may own a vertical scroll of its own.
///
/// True in the phone's fixed-height slab, where each panel has to scroll inside
/// 167pt. False in the wide sidebar, where the sidebar's own scroll runs the
/// whole stack: a panel that scrolls in there both traps the finger on the wrong
/// list and forces its section to a guessed fixed height, because a scroll view
/// has no intrinsic height to report.
private struct EditorPanelScrollsKey: EnvironmentKey {
    static let defaultValue = true
}

/// Whether a tool panel should draw its own title.
///
/// False in the wide sidebar, where the section header two rows up already says
/// "Mask" — the panel repeating it in a larger font, sometimes uppercased and
/// sometimes not, is the same name twice 44pt apart.
private struct EditorPanelShowsTitleKey: EnvironmentKey {
    static let defaultValue = true
}

/// Whether a slider row stacks its track under its label instead of sitting
/// beside it.
///
/// False on the phone, where 34pt rows are what let the 167pt parameter zone
/// hold six of them. True in the wide sidebar, which is a different trade: the
/// panel is 320pt wide and an inline row spends 88 of them on a name and 44 on
/// a number, leaving the track — the only part that is actually aimed at — a
/// third of the panel. Stacked, the same row gives the track the full width for
/// 12pt more height, which is how Lightroom, Capture One and Photos all draw a
/// develop slider on a tablet.
private struct EditorSliderStackedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var editorSliderStacked: Bool {
        get { self[EditorSliderStackedKey.self] }
        set { self[EditorSliderStackedKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var editorPanelScrolls: Bool {
        get { self[EditorPanelScrollsKey.self] }
        set { self[EditorPanelScrollsKey.self] = newValue }
    }

    var editorPanelShowsTitle: Bool {
        get { self[EditorPanelShowsTitleKey.self] }
        set { self[EditorPanelShowsTitleKey.self] = newValue }
    }
}

extension View {
    /// Wraps this content in a vertical `ScrollView` only where panels are
    /// allowed to scroll. Where they are not, the content keeps its intrinsic
    /// height and the surrounding scroll takes the overflow.
    @ViewBuilder
    func editorPanelScroll(_ scrolls: Bool) -> some View {
        if scrolls {
            ScrollView(.vertical) { self }
        } else {
            self
        }
    }
}
