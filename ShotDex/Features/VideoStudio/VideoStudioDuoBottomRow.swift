import SwiftUI

/// The Duo inner display's bottom row, 56pt (FS-12.03 §4, board DI1): the
/// five tools from x 40, 72×50 apart by 4; on the right, ending at x 907,
/// the two-line Video Settings button and Export. Media, Text, Sticker and
/// Music add to the timeline; Look opens the whole video's look in the
/// column.
struct VideoStudioDuoBottomRow: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    private typealias Geometry = VideoStudioDeskGeometry

    var body: some View {
        HStack(spacing: Geometry.duoToolGap) {
            ForEach(VideoAddTool.bottomRow) { tool in
                VideoToolbarCell(
                    command: command(for: tool),
                    size: Geometry.duoToolCell,
                    labelSize: 10
                )
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                VideoSettingsButton(model: model, isTwoLine: true)
                exportPill
            }
        }
        .padding(.leading, Geometry.duoToolLeading)
        .padding(.trailing, Geometry.duoRowTrailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1) }
    }

    private func command(for tool: VideoAddTool) -> VideoCommand {
        VideoCommand(
            title: tool.title,
            systemImage: tool.systemImage,
            isOpen: VideoStudioToolbar.panel(for: tool).map { model.activeToolPanel == $0 } ?? false,
            action: {
                switch tool {
                case .media: actions.onAddMedia()
                case .text: actions.onAddText()
                case .sticker: actions.onAddSticker()
                case .music: actions.onAddMusic()
                case .look: model.toggleToolPanel(.look)
                }
            }
        )
    }

    private var exportPill: some View {
        Button(action: actions.onExport) {
            Text("Export", comment: "Video Studio: renders the video and saves it")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: Geometry.exportHeight)
                .background(Capsule().fill(EditorTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
