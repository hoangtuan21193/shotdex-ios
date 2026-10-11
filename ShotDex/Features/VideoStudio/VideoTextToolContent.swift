import SwiftUI
import UIKit
import ShotDexKit

/// What the Text tool offers (FS-12.04 §3, FS-12.14 §3): Add Text, Auto
/// Captions with its note, then the fonts the user has reached for —
/// picking one adds a caption already wearing it. One view for the iPad
/// pool's Text tab and the Text panel of the phone and the Duo (boards
/// `TX_P_TextPanel`, `TX_DC_TextPanel`, `TX_DI_TextPanel`), so the two
/// cannot drift apart.
struct VideoTextToolContent: View {
    @Bindable var model: VideoStudioModel
    /// The phone's and the Duo's panel, or the iPad pool's tab — the
    /// Mac-style canvas's sizes there: 44pt buttons, 17pt labels, Title Case.
    var style: Style = .panel
    /// The panel's side inset: 16 on the phone, 14 on the Duo.
    var panelInset: CGFloat = 16
    /// The space over Add Text: 6 on the phone, 4 on the cover, 10 inside.
    var panelTopGap: CGFloat = 6
    let onAddText: (OverlayFontChoice?) -> Void
    let onAutoCaptions: () -> Void

    enum Style { case panel, pool }

    private typealias Pool = VideoStudioMetrics.Pool
    private var isPool: Bool { style == .pool }
    private var inset: CGFloat { isPool ? Pool.inset : panelInset }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: isPool ? 0 : panelTopGap)
                actionButton(
                    systemImage: "textformat",
                    title: VideoStudioCopy.addText,
                    identifier: "addTextButton"
                ) { onAddText(nil) }
                Color.clear.frame(height: 8)
                actionButton(
                    systemImage: "captions.bubble",
                    title: model.hasCaptionLane ? VideoStudioCopy.editCaptions : VideoStudioCopy.autoCaptions,
                    identifier: "autoCaptionsButton",
                    action: onAutoCaptions
                )
                .disabled(!model.canAutoCaption && !model.hasCaptionLane)
                .opacity(model.canAutoCaption || model.hasCaptionLane ? 1 : 0.35)
                Text(model.canAutoCaption || model.hasCaptionLane ? VideoStudioCopy.autoCaptionsNote : VideoStudioCopy.captionsUnavailable)
                    .font(.system(size: isPool ? 13 : 11))
                    .foregroundStyle(isPool ? EditorTheme.secondaryText : .white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, isPool ? inset + 4 : inset)
                    .padding(.top, 6)
                sectionTitle
                if model.fontRecents.isEmpty {
                    Text("Fonts you use appear here, ready to reuse.", comment: "Video Studio media pool: empty state for the text tab")
                        .font(.system(size: isPool ? 13 : 11.5))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .padding(.horizontal, isPool ? Pool.titleLeading : inset)
                        .padding(.top, 6)
                }
                ForEach(model.fontRecents) { font in
                    fontRow(font)
                }
            }
            .padding(.bottom, 10)
        }
        .scrollIndicators(.automatic)
    }

    /// A 48pt button on the panel (44 in the pool), corner 12, white 8 %.
    private func actionButton(
        systemImage: String, title: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: isPool ? 8 : 10) {
                // The pool's Add Text stands centred, as it always has
                // (FS-12.03b §1); every other button reads from the left.
                if isPool, identifier == "addTextButton" { Spacer(minLength: 0) }
                Image(systemName: systemImage)
                    .font(.system(size: isPool ? 17 : 16, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: isPool ? 17 : 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isPool ? 16 : 14)
            .frame(maxWidth: .infinity)
            .frame(height: isPool ? Pool.buttonHeight : VideoStudioMetrics.TextPanel.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inset)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var sectionTitle: some View {
        if isPool {
            Text(VideoStudioCopy.fontsYouUsed)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: Pool.sectionTitleHeight)
                .padding(.horizontal, Pool.titleLeading)
                .padding(.top, Pool.sectionGap)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
        } else {
            // "FONTS YOU USED", as the phone's panels write MY MUSIC.
            Text(VideoStudioCopy.fontsYouUsed.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.7))
                .frame(height: 28, alignment: .bottom)
                .padding(.bottom, 6)
                .padding(.horizontal, inset)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func fontRow(_ font: OverlayFontChoice) -> some View {
        Button { onAddText(font) } label: {
            HStack(spacing: 10) {
                Text(verbatim: "Aa")
                    .font(Self.preview(for: font, size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 40)
                Text(font.displayName)
                    .font(.system(size: isPool ? 17 : 13.5, weight: isPool ? .regular : .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isPool ? 8 : inset)
            .frame(height: isPool ? Pool.fontRowHeight : VideoStudioMetrics.TextPanel.fontRowHeight)
            .overlay(alignment: .bottom) {
                if !isPool { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isPool ? Pool.rowInset : 0)
        .accessibilityHint(Text("Adds a caption in this font", comment: "Video Studio media pool: what tapping a font row does"))
    }

    /// A font's own face at list size, the way the editor's font picker
    /// draws it.
    static func preview(for choice: OverlayFontChoice, size: CGFloat) -> Font {
        guard !choice.postScriptName.isEmpty,
              let font = UIFont(name: choice.postScriptName, size: size)
        else { return .system(size: size) }
        return Font(font)
    }
}

extension VideoStudioMetrics {
    /// The Text panel of the phone and the Duo (FS-12.04 §4, boards
    /// `TX_*_TextPanel`): 48pt buttons, 44pt font rows.
    enum TextPanel {
        static let buttonHeight: CGFloat = 48
        static let fontRowHeight: CGFloat = 44
        /// Side insets: the phone 16, the Duo 14.
        static func inset(_ windowClass: VideoStudioWindowClass?) -> CGFloat {
            windowClass == .duoCover || windowClass == .duoInner ? 14 : 16
        }
        /// Over Add Text: the phone 6, the cover 4, the inner column 14 (its
        /// content starts at the column top, the board's 4 + 10).
        static func topGap(_ windowClass: VideoStudioWindowClass?) -> CGFloat {
            switch windowClass {
            case .duoCover: 4
            case .duoInner: 14
            default: 6
            }
        }
    }
}
