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

    static func resolved(_ rawValue: String) -> EditorSidebarEdge {
        EditorSidebarEdge(rawValue: rawValue) ?? .trailing
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
    var toggle: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: group.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)
                        .foregroundStyle(isActive ? EditorTheme.accent : EditorTheme.secondaryText)
                    Text(group.title)
                        .font(EditorTheme.groupLabel)
                        .foregroundStyle(isActive ? Color.white : EditorTheme.secondaryText)
                    if hasEdits {
                        Circle()
                            .fill(EditorTheme.accent)
                            .frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EditorTheme.dimText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(height: EditorLayoutMetrics.sidebarSectionHeaderHeight)
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
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)

            if isExpanded {
                content()
                    .padding(.bottom, AppTheme.Spacing.sm)
            }

            Rectangle()
                .fill(EditorTheme.panelDivider)
                .frame(height: 1)
        }
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
            // Not hidden from assistive technology: the width is a real setting,
            // and a drag is not a route VoiceOver or Switch Control can take. The
            // ⋯ menu carries the same three widths for anyone who cannot drag.
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

extension EnvironmentValues {
    var editorPanelScrolls: Bool {
        get { self[EditorPanelScrollsKey.self] }
        set { self[EditorPanelScrollsKey.self] = newValue }
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
