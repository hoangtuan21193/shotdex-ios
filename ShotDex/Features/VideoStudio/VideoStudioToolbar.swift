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

    private var commands: [VideoCommand] {
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
            Button(action: actions.onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.1fs · %@ · 30fps", model.totalDuration, model.recipe.renderPreset.displayName))
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

/// One toolbar cell — the command band's cell shape, sized for a scrolling row.
private struct VideoToolbarCell: View {
    let command: VideoCommand

    var body: some View {
        Button(action: command.action) {
            VStack(spacing: 5) {
                // Fixed glyph box: a tall symbol (photo.badge.plus) otherwise pushes
                // its label lower than its neighbours'.
                Image(systemName: command.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 22)
                Text(command.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(tintColor)
            .frame(width: VideoStudioMetrics.commandCellWidth, height: 52)
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
