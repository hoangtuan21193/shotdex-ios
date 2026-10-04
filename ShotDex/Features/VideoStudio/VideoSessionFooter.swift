import SwiftUI

/// ✕ · name · ✓ (FS-12.04 §5, board P2): while an item is selected the
/// phone's bottom row is this, not the tools. ✕ puts the project back as it
/// was when the item was selected; ✓ keeps every change. The ✓ is a white
/// disc with a black glyph — accent belongs to Export alone.
struct VideoSessionFooter: View {
    let title: VideoItemTitle.Lines
    let onCancel: () -> Void
    let onCommit: () -> Void
    /// The phone's row is 62 with 44pt discs; the iPad inspector's foot is
    /// 58 (60 in the portrait dock) with 40pt discs (FS-12.03 §2–3).
    var height: CGFloat = VideoStudioMetrics.toolbarHeight
    var buttonSize: CGFloat = VideoStudioMetrics.sessionButton

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(Color(red: 24 / 255, green: 24 / 255, blue: 26 / 255).opacity(0.82)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VideoStudioCopy.discardChanges)

            VStack(spacing: 1) {
                Text(title.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(title.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(Color.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VideoStudioCopy.keepChanges)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1) }
    }
}
