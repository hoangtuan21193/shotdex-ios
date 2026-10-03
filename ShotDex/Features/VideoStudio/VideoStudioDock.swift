import SwiftUI

/// The iPad portrait dock (FS-12.03 §3): the controls under the timeline,
/// 324pt, the whole width — portrait has height to spare and no width, so
/// the panel spends height. Rounded at the top, a 1pt white-7 % rule above.
/// Nothing selected: "Look · Whole video" with Media · Text · Sticker ·
/// Music beside the title. A tool open or an item selected: its panel.
struct VideoStudioDock: View {
    @Bindable var model: VideoStudioModel
    let actions: VideoInspectorActions
    let importedMusic: ImportedMusicStore

    var body: some View {
        VideoStudioSheetHost(
            model: model,
            actions: actions,
            layout: .column,
            importedMusic: importedMusic,
            showsIdleLook: true,
            idleTools: [.media, .text, .sticker, .music]
        )
        .background(EditorTheme.panelSolid)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: VideoStudioDeskGeometry.inspectorCornerRadius,
                topTrailing: VideoStudioDeskGeometry.inspectorCornerRadius
            ),
            style: .continuous
        ))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: VideoStudioDeskGeometry.inspectorCornerRadius,
                    topTrailing: VideoStudioDeskGeometry.inspectorCornerRadius
                ),
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            // Only the top edge and its corners: the rule is above the dock,
            // not around it.
            .mask(alignment: .top) {
                Rectangle().frame(height: VideoStudioDeskGeometry.inspectorCornerRadius)
            }
            .allowsHitTesting(false)
        }
    }
}
