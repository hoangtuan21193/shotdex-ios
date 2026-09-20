import SwiftUI

/// Geometry for the Collections tab's cover tiles.
///
/// One number, two values: a tile is **112pt on a phone and 168pt on a
/// regular-width window**. That is a deliberate exception to `DESIGN.md`
/// §10.1c ("a wide screen gets more content, not bigger content"), argued in
/// §10.1d: the tile is a *cover*, and a cover is the content — a bigger cover
/// on a bigger screen is more of the picture you are trying to recognise, not
/// the same picture inflated. Photos on iPad makes the same call and goes
/// further, letting the user pick Large, Small or Mixed tiles.
enum AlbumTileMetrics {
    static let compactSide: CGFloat = 112
    static let regularSide: CGFloat = 168

    static func side(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? regularSide : compactSide
    }

    /// Gap between the cover and its caption.
    static let captionSpacing: CGFloat = 6
    /// The glyph shown when a tile has no cover. Scaled to the tile, because a
    /// body-sized symbol in a 168pt square reads as an image that failed to
    /// load rather than as a deliberate icon.
    static func placeholderGlyphSize(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 44 : 30
    }
}

/// One tile on the Collections tab: a square cover with the name and a second
/// line under it.
///
/// Replaces the four near-identical row tokens this screen used to carry
/// (album, smart album, utility, duplicates), which were the same layout
/// written out four times and kept in sync by hand. The shape changed with
/// them: a 60pt row with a 44pt thumbnail is a settings row, and this tab is
/// for recognising a collection by its picture.
struct AlbumCoverTile<Cover: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var cover: () -> Cover

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .subheadline) private var typeScale = 1.0

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var side: CGFloat { AlbumTileMetrics.side(isRegularWidth: isRegularWidth) * typeScale }

    var body: some View {
        VStack(alignment: .leading, spacing: AlbumTileMetrics.captionSpacing) {
            cover()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // The caption is as wide as the cover and no wider, so a long
            // album name truncates inside its own tile instead of pushing the
            // next one sideways.
            .frame(width: side, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
    }
}

/// The well a tile's cover sits in: the image if there is one, the glyph if
/// there is not. Kept here so every tile's empty state looks the same.
struct AlbumCoverWell: View {
    let image: UIImage?
    let systemImage: String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(
                            size: AlbumTileMetrics.placeholderGlyphSize(
                                isRegularWidth: horizontalSizeClass == .regular
                            ),
                            weight: .light
                        ))
                        .foregroundStyle(.tertiary)
                }
            }
    }
}
