import SwiftUI

/// One tile of a "choose a kind" grid (FS-03.13c §1) — Mask's areas, Markup's
/// layers: the kind's glyph over its short name, 60pt tall.
struct EditorKindTileLabel: View {
    let title: String
    let systemImage: String

    static let height: CGFloat = 60

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
            Text(title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .minimumScaleFactor(EditorLayoutMetrics.editorPanelRowMinimumScale)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}

/// The tile's idle fill (white 6%, `r-md`) and pressed dim.
struct EditorKindTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        configuration.label
            .background(EditorTheme.chipIdle, in: shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}
