import SwiftUI

/// The always-present tool row under the timeline: the five tools that add
/// to the timeline, plus Look (FS-12.04 §2–3). Five 72×52 cells across the
/// width, no scrolling — five is all there is. The cell whose panel is open
/// sits on white 14 %; tapping it again closes the panel and keeps it.
struct VideoStudioToolbar: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    var body: some View {
        HStack(spacing: 0) {
            ForEach(commands) { command in
                VideoToolbarCell(command: command)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, VideoStudioMetrics.toolRowInset)
        .frame(height: VideoStudioMetrics.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1) }
    }

    /// `true` where a media pool column stands beside the stage and can carry
    /// the *insert* commands — Resolve puts them on the library, not on a
    /// tool rail, because "add a clip" and "open the colour controls" are not
    /// the same kind of thing and should not look alike.
    var poolCarriesInserts = false

    /// What the row holds, in order: `VideoAddTool`'s one list.
    static func tools(poolCarriesInserts: Bool) -> [VideoAddTool] {
        poolCarriesInserts ? VideoAddTool.poolRow : VideoAddTool.bottomRow
    }

    var commands: [VideoCommand] {
        Self.tools(poolCarriesInserts: poolCarriesInserts).map { tool in
            VideoCommand(
                title: tool.title,
                systemImage: tool.systemImage,
                isOpen: Self.panel(for: tool).map { model.activeToolPanel == $0 } ?? false,
                action: action(for: tool)
            )
        }
    }

    /// The panel a tool's cell opens, when it opens one.
    static func panel(for tool: VideoAddTool) -> VideoToolPanel? {
        switch tool {
        case .look: .look
        case .music: .music
        case .media, .text, .sticker: nil
        }
    }

    private func action(for tool: VideoAddTool) -> () -> Void {
        switch tool {
        case .media: actions.onAddMedia
        case .text: actions.onAddText
        case .sticker: actions.onAddSticker
        case .music: actions.onAddMusic
        case .look: { model.toggleToolPanel(.look) }
        }
    }
}

/// The same tools as a **vertical rail**, for a regular-width window.
///
/// A row of nine cells across 1032pt is a row with 560pt of nothing in it, and
/// the horizontal band steals height from the thing the screen is for. Final
/// Cut and CapCut both put the tools down the side on iPad for the same
/// reason: vertical space is what a timeline editor is short of, and a rail
/// costs none of it.
struct VideoStudioToolRail: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    /// See `VideoStudioToolbar.poolCarriesInserts`.
    var poolCarriesInserts = false
    /// Clears the status bar and the command band, so the first cell starts
    /// level with the preview rather than under the clock.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// The rail's own height, so a short window can stop paying for the
    /// alignment inset.
    var availableHeight: CGFloat = .greatestFiniteMagnitude

    /// Nine cells plus their gaps.
    private var contentHeight: CGFloat {
        CGFloat(commands.count) * VideoStudioMetrics.railCellHeight
            + CGFloat(max(0, commands.count - 1)) * 6
    }

    /// Lining the first cell up with the preview costs the band's height, and
    /// on a short window that is what pushes the last tool off the bottom —
    /// measured on the iPhone Duo's inner display (669pt), where Background
    /// was drawn half-cut. Alignment is worth less than a tool you can see,
    /// so the inset gives way first; the rail still scrolls either way.
    private var effectiveTopInset: CGFloat {
        let needed = contentHeight + 24 + bottomInset
        let spare = availableHeight - needed
        return max(0, min(topInset, spare))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(commands) { VideoToolbarCell(command: $0, isRegularWidth: true) }
            }
            .padding(.top, effectiveTopInset + 12)
            .padding(.bottom, bottomInset + 12)
            .frame(maxWidth: .infinity)
        }
        .frame(width: VideoStudioMetrics.railWidth)
        .frame(maxHeight: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .trailing) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(width: 1)
        }
    }

    private var commands: [VideoCommand] {
        VideoStudioToolbar(model: model, actions: actions, poolCarriesInserts: poolCarriesInserts).commands
    }
}

/// One toolbar cell — the command band's cell shape, sized for a scrolling row.
private struct VideoToolbarCell: View {
    let command: VideoCommand
    /// On a big screen the cell keeps its shape but reads at desk distance:
    /// a 20pt glyph and an 11pt label instead of 17 and 9.5.
    var isRegularWidth = false

    var body: some View {
        Button(action: command.action) {
            VStack(spacing: 5) {
                // Fixed glyph box: a tall symbol (photo.badge.plus) otherwise pushes
                // its label lower than its neighbours'.
                Image(systemName: command.systemImage)
                    .font(.system(size: isRegularWidth ? 20 : 19, weight: .regular))
                    .frame(height: isRegularWidth ? 26 : 22)
                Text(command.title)
                    .font(.system(size: isRegularWidth ? 11 : 10, weight: .medium))
                    .lineLimit(1)
                    // Not `fixedSize()`: that turns off SwiftUI's own
                    // compression, so a label longer than the 52pt cell —
                    // "Hinzufügen" for Add, "Aufkleber" for Sticker — draws
                    // straight over its neighbour instead of shrinking.
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tintColor)
            .frame(
                width: isRegularWidth ? VideoStudioMetrics.railWidth - 12 : VideoStudioMetrics.toolCellSize.width,
                height: isRegularWidth ? VideoStudioMetrics.railCellHeight : VideoStudioMetrics.toolCellSize.height
            )
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                    .fill(command.isOpen ? VideoStudioMetrics.openCellFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(command.isOpen ? .isSelected : [])
    }

    private var tintColor: Color {
        switch command.tint {
        case .accent: EditorTheme.accent
        case .destructive: EditorTheme.timelineDestructive
        case .normal: .white
        }
    }
}
