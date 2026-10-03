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

/// One tool cell: a glyph over its label, white 14 % while its panel is
/// open. The phone's row draws 72×52; the Duo's bottom row and cover rail
/// pass their own sizes.
struct VideoToolbarCell: View {
    let command: VideoCommand
    var size: CGSize = VideoStudioMetrics.toolCellSize
    var labelSize: CGFloat = 10

    var body: some View {
        Button(action: command.action) {
            VStack(spacing: 5) {
                // Fixed glyph box: a tall symbol (photo.badge.plus) otherwise pushes
                // its label lower than its neighbours'.
                Image(systemName: command.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 22)
                Text(command.title)
                    .font(.system(size: labelSize, weight: .medium))
                    .lineLimit(1)
                    // Not `fixedSize()`: that turns off SwiftUI's own
                    // compression, so a label longer than the 52pt cell —
                    // "Hinzufügen" for Add, "Aufkleber" for Sticker — draws
                    // straight over its neighbour instead of shrinking.
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tintColor)
            .frame(width: size.width, height: size.height)
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
