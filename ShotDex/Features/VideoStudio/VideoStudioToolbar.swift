import SwiftUI

/// The always-present tool row under the timeline. It carries what applies to
/// the whole project — the add buttons and the project-wide tools — so nothing
/// is selected the sheet stays down and the preview keeps the height.
struct VideoStudioToolbar: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(commands) { VideoToolbarCell(command: $0) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: VideoStudioMetrics.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1) }
    }

    var commands: [VideoCommand] {
        [
            // Plain like Text / Sticker / Music: accent marks the *open* global
            // tool, and Add is an action, not a mode.
            VideoCommand(title: "Add", systemImage: "plus", action: actions.onAddMedia),
            VideoCommand(title: "Text", systemImage: "textformat", action: actions.onAddText),
            VideoCommand(title: "Sticker", systemImage: "photo.badge.plus", action: actions.onAddSticker),
            VideoCommand(title: "Music", systemImage: "music.note", action: actions.onAddMusic),
            globalCommand(.ratio),
            globalCommand(.filters),
            globalCommand(.adjustments),
            globalCommand(.masterVolume),
            globalCommand(.background),
        ]
    }

    private func globalCommand(_ tool: VideoStudioModel.GlobalTool) -> VideoCommand {
        VideoCommand(
            title: tool.titleKey,
            systemImage: tool.systemImage,
            tint: model.activeGlobalTool == tool ? .accent : .normal
        ) {
            model.showGlobalTool(model.activeGlobalTool == tool ? nil : tool)
        }
    }
}

/// The bottom bar: Back on the leading edge, the export estimate in the middle,
/// the Export pill on the trailing edge. Always visible — the contextual panel
/// slides over it rather than replacing it.
struct VideoStudioBottomBar: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    var body: some View {
        HStack(spacing: 12) {
            // The same Back the top band draws at rail width, drawn the same
            // way: glass, not a flat disc. Widening an iPad window past the
            // rail threshold moves this button into the top band, and it
            // used to change material on the way.
            Button(action: actions.onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background { Color.clear.editorGlass(Circle()) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))

            VStack(alignment: .leading, spacing: 1) {
                Text(VideoStudioMetrics.exportReadout(
                duration: model.totalDuration,
                presetName: model.recipe.renderPreset.displayName
            ))
                    .font(.system(size: 11).monospacedDigit())
                Text("~\(sizeText)")
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(EditorTheme.dimText)

            Spacer(minLength: 0)

            Button(action: actions.onExport) {
                Text("Export")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Capsule().fill(EditorTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: VideoStudioMetrics.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: model.estimatedExportBytes, countStyle: .file)
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
    /// Clears the status bar and the command band, so the first cell starts
    /// level with the preview rather than under the clock.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(commands) { VideoToolbarCell(command: $0, isRegularWidth: true) }
            }
            .padding(.top, topInset + 12)
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
        VideoStudioToolbar(model: model, actions: actions).commands
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
                    .font(.system(size: isRegularWidth ? 20 : 17, weight: .regular))
                    .frame(height: isRegularWidth ? 26 : 22)
                Text(command.title)
                    .font(.system(size: isRegularWidth ? 11 : 9.5, weight: .medium))
                    .lineLimit(1)
                    // Not `fixedSize()`: that turns off SwiftUI's own
                    // compression, so a label longer than the 52pt cell —
                    // "Hinzufügen" for Add, "Aufkleber" for Sticker — draws
                    // straight over its neighbour instead of shrinking.
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tintColor)
            .frame(
                width: isRegularWidth ? VideoStudioMetrics.railWidth - 12 : VideoStudioMetrics.commandCellWidth,
                height: isRegularWidth ? VideoStudioMetrics.railCellHeight : 52
            )
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.commandCellRadius, style: .continuous)
                    .fill(command.tint == .accent ? EditorTheme.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tintColor: Color {
        switch command.tint {
        case .accent: EditorTheme.accent
        case .destructive: EditorTheme.timelineDestructive
        case .normal: .white
        }
    }
}
