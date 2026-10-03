import SwiftUI

/// The Duo cover's 84pt trailing rail (FS-12.07b §3, board DC1): iOS keeps
/// the strip for its vertical status bar, and the studio hides the status
/// bar, so the strip is the tools' — which gives the content its 382pt.
///
/// A cap of diagonal stripes over the camera hole and the top corner (y
/// 0–72, nothing to touch); the five tools as 64×56 cells from y 80; then,
/// at thumb height, Video Settings and Export — or, while an item is
/// selected, its name, ✕ and ✓, with the tools at 30 % and inert.
struct VideoStudioDuoCoverRail: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions

    private typealias Geometry = VideoStudioDeskGeometry

    /// The window's width: the rail's parts are placed in window
    /// coordinates, less the rail's own x.
    let windowWidth: CGFloat

    private var isSelecting: Bool { model.inspectorTarget != .none }
    private var parts: Geometry.CoverRail {
        Geometry.coverRail(windowWidth: windowWidth, toolCount: VideoAddTool.bottomRow.count)
    }
    private var railX: CGFloat { windowWidth - Geometry.coverRailWidth }

    var body: some View {
        let toolsInert = VideoAddTool.toolsAreInert(in: .duoCover, isSelecting: isSelecting)
        ZStack(alignment: .topLeading) {
            EditorTheme.panelSolid
            cap
                .frame(width: parts.cap.width, height: parts.cap.height)
            ForEach(Array(VideoAddTool.bottomRow.enumerated()), id: \.element) { index, tool in
                VideoToolbarCell(command: command(for: tool), size: Geometry.coverToolCell, labelSize: 9.5)
                    .opacity(toolsInert ? 0.3 : 1)
                    .allowsHitTesting(!toolsInert)
                    .offset(x: parts.tools[index].minX - railX, y: parts.tools[index].minY)
            }
            if isSelecting, let title = model.selectionTitle {
                VStack(spacing: 2) {
                    Text(title.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(title.detail)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: parts.name.width, height: parts.name.height)
                .accessibilityElement(children: .combine)
                .offset(x: parts.name.minX - railX, y: parts.name.minY)
                disc(at: parts.upperAction) {
                    Button { model.cancelSession() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Geometry.coverActionDisc, height: Geometry.coverActionDisc)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VideoStudioCopy.discardChanges)
                }
                disc(at: parts.lowerAction) {
                    Button { model.commitSession() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: Geometry.coverActionDisc, height: Geometry.coverActionDisc)
                            .background(Circle().fill(Color.white))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VideoStudioCopy.keepChanges)
                }
            } else {
                disc(at: parts.upperAction) { videoSettingsDisc }
                disc(at: parts.lowerAction) {
                    Button(action: actions.onExport) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: Geometry.coverActionDisc, height: Geometry.coverActionDisc)
                            .background(Circle().fill(EditorTheme.accent))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Export", comment: "Video Studio: renders the video and saves it"))
                }
            }
        }
        .frame(width: Geometry.coverRailWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(width: 1)
        }
    }

    /// Dark diagonal stripes: the strip under the camera hole and the
    /// corner, marked as not for touching.
    private var cap: some View {
        Canvas { context, size in
            let step: CGFloat = 8
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 3)
                x += step
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func disc(at frame: CGRect, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX - railX, y: frame.minY)
    }

    /// Video Settings, drawn as the project's own shape.
    private var videoSettingsDisc: some View {
        let ratio = model.recipe.aspect.ratio
        let side: CGFloat = 20
        let isOpen = model.activeToolPanel == .videoSettings
        return Button {
            model.toggleToolPanel(.videoSettings)
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(isOpen ? Color.black : Color.white, lineWidth: 1.8)
                .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
                .frame(width: Geometry.coverActionDisc, height: Geometry.coverActionDisc)
                .background(Circle().fill(isOpen ? Color.white : Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VideoStudioCopy.videoSettings)
        .accessibilityValue(model.recipe.aspect.displayName)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
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
}
