import GameController
import SwiftUI

/// The keyboard's shortcut list on the phone (board F6_P_Keyboard) and the
/// Duo's cover (F6_DC_Keyboard), FS-12.17b §4: in the panel's place, 340
/// tall over the tool row — a 46pt head (keyboard glyph · "Keyboard
/// Shortcuts" · ✕), "Keyboard connected", then the twelve folded rows, 32
/// each, scrolling. It does not cover the frame, so it may stay.
struct VideoShortcutListCard: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: true) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: VideoStudioMetrics.ShortcutList.topGap)
                    connectedRow
                    ForEach(Array(VideoShortcut.compactRows.enumerated()), id: \.offset) { _, row in
                        shortcutRow(row)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
            // The keyboard unplugged: nothing here works any more.
            if GCKeyboard.coalesced == nil { model.closeShortcutList() }
        }
        .accessibilityIdentifier("shortcutList")
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .accessibilityHidden(true)
            Text(VideoStudioCopy.keyboardShortcutsTitle)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                model.closeShortcutList()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VideoStudioCopy.close)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: VideoStudioMetrics.ShortcutList.headerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var connectedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 17)
                .accessibilityHidden(true)
            Text(VideoStudioCopy.keyboardConnected)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(VideoStudioCopy.holdCommandHint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: VideoStudioMetrics.ShortcutList.connectedRowHeight)
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(_ row: [VideoShortcut]) -> some View {
        HStack(spacing: 10) {
            Text(VideoStudioCopy.shortcutRowName(row))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: VideoStudioMetrics.ShortcutList.keycapGap) {
                ForEach(Array(VideoShortcut.keycaps(row).enumerated()), id: \.offset) { _, cap in
                    VideoKeycap(text: cap)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: VideoStudioMetrics.ShortcutList.rowHeight)
        // The hairline under the row, not in it: 33 a row, as the board.
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VideoStudioCopy.shortcutRowSpoken(row))
    }
}

/// One keycap: at least 24×24, corner 6, monospaced 12 (FS-12.17b §4).
struct VideoKeycap: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: VideoStudioMetrics.ShortcutList.keycapSide, minHeight: VideoStudioMetrics.ShortcutList.keycapSide)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.12))
            )
            .fixedSize()
    }
}

extension VideoStudioMetrics {
    /// The keyboard's shortcut list (FS-12.17b §4, F6_P_Keyboard).
    enum ShortcutList {
        static let headerHeight: CGFloat = 46
        static let topGap: CGFloat = 6
        static let connectedRowHeight: CGFloat = 36
        static let rowHeight: CGFloat = 32
        static let keycapSide: CGFloat = 24
        static let keycapGap: CGFloat = 3
        /// Where the first row starts under the card's top: 46 + 6 + 36.
        static var firstRowTop: CGFloat { headerHeight + topGap + connectedRowHeight }
    }
}
