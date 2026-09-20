import SwiftUI
import UIKit

/// Geometry for the Collections tab's cover tiles.
///
/// One number, two values: a tile is **132pt on a phone and 192pt on a
/// regular-width window**. That is a deliberate exception to `DESIGN.md`
/// §10.1c ("a wide screen gets more content, not bigger content"), argued in
/// §10.1d: the tile is a *cover*, and a cover is the content — a bigger cover
/// on a bigger screen is more of the picture you are trying to recognise, not
/// the same picture inflated. Photos on iPad makes the same call and goes
/// further, letting the user pick Large, Small or Mixed tiles.
enum AlbumTileMetrics {
    static let compactSide: CGFloat = 132
    static let regularSide: CGFloat = 192

    static func side(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? regularSide : compactSide
    }

    /// The memory card beside these tiles is the same kind of thing — a cover
    /// you recognise a moment by, one of a row you scan — so it grows on the
    /// same terms. It is wide rather than square, so only its width is the
    /// axis the row reveals more of; the height follows to keep the shape.
    static let compactMemory = CGSize(width: 260, height: 150)
    static let regularMemory = CGSize(width: 360, height: 208)

    static func memorySize(isRegularWidth: Bool) -> CGSize {
        isRegularWidth ? regularMemory : compactMemory
    }

    /// The glyph shown when a tile has no cover. Scaled to the tile, because a
    /// body-sized symbol in a 192pt square reads as an image that failed to
    /// load rather than as a deliberate icon.
    static func placeholderGlyphSize(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 44 : 30
    }

    /// The bottom slice of a cover the title sits over, as a fraction of the
    /// tile's height. Also the slice whose brightness decides whether that
    /// title needs anything behind it.
    static let titleBandFraction: CGFloat = 0.42
}

/// Whether a cover needs darkening behind its title — measured, not assumed.
///
/// A fixed scrim on every cover is the usual answer and it is wrong twice: it
/// dirties a photo that was already dark down there, and on a white sky it is
/// never quite enough. This reads the average brightness of the strip the
/// title actually sits on and only asks for a scrim when that strip is
/// bright.
enum CoverTitleScrim {
    /// Above this average luminance (0…1), white text stops being
    /// comfortable and the scrim goes on.
    static let brightnessThreshold: Double = 0.42

    /// Average luminance of the bottom `fraction` of the image, or nil when
    /// it cannot be read.
    ///
    /// One Core Graphics draw into a single pixel — the whole strip averaged
    /// by the resampler — and it happens once, when the cover arrives, not
    /// per frame.
    static func bottomLuminance(
        of image: UIImage,
        fraction: CGFloat = AlbumTileMetrics.titleBandFraction
    ) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let stripHeight = max(1, Int(CGFloat(cgImage.height) * fraction))
        guard let strip = cgImage.cropping(to: CGRect(
            x: 0,
            y: cgImage.height - stripHeight,
            width: cgImage.width,
            height: stripHeight
        )) else { return nil }

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        // Rec. 709 luma, not a plain RGB mean: green carries most of
        // perceived brightness, so an even average calls a saturated blue sky
        // darker than it reads.
        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Bright covers get a scrim. A cover that cannot be read gets one too —
    /// an unreadable name is the worse failure of the two.
    static func isNeeded(for image: UIImage) -> Bool {
        guard let luminance = bottomLuminance(of: image) else { return true }
        return luminance > brightnessThreshold
    }
}

/// One tile on the Collections tab: a square cover with its name **over** the
/// bottom of it.
///
/// The name used to sit under the cover. Inside the tile it belongs to the
/// picture it names, and the tile gets the caption's height back — which is
/// where the extra size came from.
///
/// Counts are not drawn. They are still spoken (`accessibilityLabel` carries
/// "42 photos"), but a number beside every name is noise on a screen whose
/// whole job is "which one is this".
struct AlbumCoverTile<Cover: View>: View {
    let title: String
    /// What VoiceOver says. Explicit rather than assembled from the title,
    /// because the count it should mention is no longer drawn anywhere.
    let accessibilityLabel: String
    /// Set when the cover is a photo bright enough to swallow white text.
    /// A tile with no photo leaves it false and gets no scrim at all.
    var needsScrim = false
    @ViewBuilder var cover: () -> Cover

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .subheadline) private var typeScale = 1.0

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var side: CGFloat { AlbumTileMetrics.side(isRegularWidth: isRegularWidth) * typeScale }

    var body: some View {
        cover()
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) { scrim }
            .overlay(alignment: .bottomLeading) { name }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var scrim: some View {
        if needsScrim {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: side * AlbumTileMetrics.titleBandFraction)
            .allowsHitTesting(false)
        }
    }

    private var name: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            // Two lines, then truncate: one line cut "Recently Added" in half
            // on a phone, and three would cover the picture the tile exists
            // to show.
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            // A cover dark enough to skip the scrim can still have a bright
            // speck behind one letter.
            .shadow(color: .black.opacity(needsScrim ? 0.3 : 0.7), radius: 3, y: 1)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .frame(width: side, alignment: .leading)
    }
}

/// The well a tile's cover sits in: the image if there is one, the glyph if
/// there is not. Kept here so every tile's empty state looks the same.
///
/// The empty surface is a mid grey rather than `secondarySystemBackground`,
/// because the title is drawn on top of it in white now and a tile with no
/// cover must not read as a different component from one with a cover.
struct AlbumCoverWell: View {
    let image: UIImage?
    let systemImage: String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if let image {
                Color.clear.overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Color(.systemGray3).overlay {
                    Image(systemName: systemImage)
                        .font(.system(
                            size: AlbumTileMetrics.placeholderGlyphSize(
                                isRegularWidth: horizontalSizeClass == .regular
                            ),
                            weight: .light
                        ))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .clipped()
    }
}
