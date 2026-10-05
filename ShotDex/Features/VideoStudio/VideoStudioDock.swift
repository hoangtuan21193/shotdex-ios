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
        VStack(spacing: 0) {
            VideoStudioSheetHost(
                model: model,
                actions: actions,
                layout: .dock,
                importedMusic: importedMusic,
                showsIdleLook: true,
                idleTools: [.media, .text, .sticker, .music]
            )
            // Selected: the command row, three columns of controls, then
            // ✕ · name · ✓, 64 at dock + 260 (FS-12.03 §3). The add buttons
            // make way for the commands.
            if let title = model.sessionFooterTitle {
                VideoSessionFooter(
                    title: title,
                    onCancel: { model.cancelSession() },
                    onCommit: { model.commitSession() },
                    height: VideoStudioDeskGeometry.dockFooterHeight,
                    buttonSize: VideoStudioDeskGeometry.deskFooterButton,
                    style: .desk
                )
            }
        }
        .background(EditorTheme.panelSolid)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: VideoStudioDeskGeometry.dockCornerRadius,
                topTrailing: VideoStudioDeskGeometry.dockCornerRadius
            ),
            style: .continuous
        ))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: VideoStudioDeskGeometry.dockCornerRadius,
                    topTrailing: VideoStudioDeskGeometry.dockCornerRadius
                ),
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            // Only the top edge and its corners: the rule is above the dock,
            // not around it.
            .mask(alignment: .top) {
                Rectangle().frame(height: VideoStudioDeskGeometry.dockCornerRadius)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Three columns of the dock's width shared out — 312 each on a 1032
/// window, `gap` apart with a 1pt rule in the middle of each gap, 16 in.
struct DockColumns<First: View, Second: View, Third: View>: View {
    let gap: CGFloat
    @ViewBuilder let first: First
    @ViewBuilder let second: Second
    @ViewBuilder let third: Third

    init(gap: CGFloat, @ViewBuilder _ first: () -> First, @ViewBuilder second: () -> Second, @ViewBuilder third: () -> Third) {
        self.gap = gap
        self.first = first()
        self.second = second()
        self.third = third()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            first.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            rule
            second.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            rule
            third.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, VideoStudioDeskGeometry.dockInset)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .padding(.horizontal, (gap - 1) / 2)
    }
}
