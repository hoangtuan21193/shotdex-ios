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
        // An item's session or the Media panel's (FS-12.09 §3): ✕ · name ·
        // ✓ takes Video Settings' and Export's place. Only an item makes
        // the tools inert.
        let title = model.sessionFooterTitle
        let toolsInert = VideoAddTool.toolsAreInert(in: .duoInner, isSelecting: model.selectionTitle != nil)
        HStack(spacing: Geometry.duoToolGap) {
            // While an item is selected the tools stay where they are, at
            // white 30 % and taking no touches (FS-12.03 §4): the row does
            // not jump, and nothing is added behind an open session.
            ForEach(VideoAddTool.bottomRow) { tool in
                VideoToolbarCell(
                    command: command(for: tool),
                    size: Geometry.duoToolCell,
                    labelSize: 10
                )
                .opacity(toolsInert ? 0.3 : 1)
                .allowsHitTesting(!toolsInert)
            }
            Spacer(minLength: 0)
            if let title {
                sessionGroup(title)
            } else {
                HStack(spacing: 10) {
                    VideoSettingsButton(model: model, style: .twoLine)
                    exportPill
                }
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

    /// ✕ · name · ✓ in place of Video Settings and Export, x 620–907: the
    /// session ends where the thumb of the right hand already is. Export is
    /// hidden — exporting half way through an open session would export
    /// something the user has not decided on.
    private func sessionGroup(_ title: VideoItemTitle.Lines) -> some View {
        HStack(spacing: 0) {
            Button { model.cancelSession() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Geometry.footerButton, height: Geometry.footerButton)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VideoStudioCopy.discardChanges)
            VStack(spacing: 1) {
                Text(title.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(title.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Button { model.commitSession() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: Geometry.footerButton, height: Geometry.footerButton)
                    .background(Circle().fill(Color.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VideoStudioCopy.keepChanges)
        }
        .frame(width: Geometry.duoSessionGroupWidth)
    }

    private var exportPill: some View {
        Button(action: actions.onExport) {
            Text("Export", comment: "Video Studio: renders the video and saves it")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: Geometry.duoExportHeight)
                .background(Capsule().fill(EditorTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
