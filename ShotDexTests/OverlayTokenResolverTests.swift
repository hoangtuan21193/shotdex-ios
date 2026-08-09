import Foundation
import Testing
@testable import ShotDex

struct OverlayTokenResolverTests {
    private let full = OverlayTokenValues(
        camera: "Canon EOS R6",
        lens: "RF 85mm F1.2 L USM",
        focal: "85mm",
        aperture: "f/1.2",
        shutter: "1/500",
        iso: "ISO 400",
        date: "19 July 2026",
        filename: "IMG_1234.CR3"
    )

    @Test func everyTokenSubstitutes() {
        for token in OverlayToken.allCases {
            let resolved = OverlayTokenResolver.resolve(token.placeholder, values: full)
            #expect(resolved == full.value(for: token))
        }
    }

    @Test func plainTextPassesThroughUntouched() {
        let template = "© Tuan Hoang 2026"
        #expect(OverlayTokenResolver.resolve(template, values: .empty) == template)
    }

    /// The whole point of the segment machinery: a photo with no lens tag must not
    /// render "Canon EOS R6 ·  · 85mm".
    @Test func aMissingTokenTakesItsSeparatorWithIt() {
        var values = full
        values.lens = nil
        let resolved = OverlayTokenResolver.resolve(
            "{camera} · {lens} · {focal}",
            values: values
        )
        #expect(resolved == "Canon EOS R6 · 85mm")
    }

    /// A segment exists to introduce its token, so the prose goes when the value
    /// does — "Shot on" alone is worse than nothing.
    @Test func aMissingTokenTakesItsProseWithIt() {
        let resolved = OverlayTokenResolver.resolve(
            "Shot on {camera} · {focal}",
            values: OverlayTokenValues(focal: "85mm")
        )
        #expect(resolved == "85mm")
    }

    @Test func aSegmentKeepsProseWhenAnyOfItsTokensResolved() {
        let resolved = OverlayTokenResolver.resolve(
            "Shot on {camera} at {aperture}",
            values: OverlayTokenValues(camera: "Canon EOS R6")
        )
        #expect(resolved == "Shot on Canon EOS R6 at")
    }

    @Test func aTrailingSeparatorIsNotLeftBehind() {
        let resolved = OverlayTokenResolver.resolve(
            "{camera} · {lens}",
            values: OverlayTokenValues(camera: "Canon EOS R6")
        )
        #expect(resolved == "Canon EOS R6")
    }

    @Test func aLeadingSeparatorIsNotLeftBehind() {
        let resolved = OverlayTokenResolver.resolve(
            "{camera} · {lens}",
            values: OverlayTokenValues(lens: "RF 85mm")
        )
        #expect(resolved == "RF 85mm")
    }

    @Test func theTemplateSeparatorIsReused() {
        var values = full
        values.lens = nil
        #expect(
            OverlayTokenResolver.resolve("{camera} | {lens} | {focal}", values: values)
                == "Canon EOS R6 | 85mm"
        )
        #expect(
            OverlayTokenResolver.resolve("{camera}, {lens}, {focal}", values: values)
                == "Canon EOS R6, 85mm"
        )
        #expect(
            OverlayTokenResolver.resolve("{camera} — {lens} — {focal}", values: values)
                == "Canon EOS R6 — 85mm"
        )
    }

    /// A slash or dash only separates when it stands between spaces, so an unspaced
    /// one in the user's own prose survives.
    @Test func anUnspacedSlashIsNotASeparator() {
        let resolved = OverlayTokenResolver.resolve(
            "{camera}/{lens}",
            values: OverlayTokenValues(camera: "Canon EOS R6")
        )
        #expect(resolved == "Canon EOS R6/")
    }

    @Test func anUnknownTokenStaysLiteral() {
        let resolved = OverlayTokenResolver.resolve("{camera} {foo}", values: full)
        #expect(resolved == "Canon EOS R6 {foo}")
    }

    /// A line of pure prose has no tokens, so it never goes through the segment
    /// machinery and never loses a token-only neighbour's blank line.
    @Test func multilineResolvesEachLineIndependently() {
        var values = full
        values.lens = nil
        let resolved = OverlayTokenResolver.resolve(
            "© Tuan Hoang\n{camera} · {lens}\n{iso}",
            values: values
        )
        #expect(resolved == "© Tuan Hoang\nCanon EOS R6\nISO 400")
    }

    @Test func aLineThatResolvesToNothingIsDropped() {
        let resolved = OverlayTokenResolver.resolve(
            "© Tuan Hoang\n{camera} · {lens}",
            values: .empty
        )
        #expect(resolved == "© Tuan Hoang")
    }

    @Test func aDeliberatelyBlankLineSurvives() {
        let resolved = OverlayTokenResolver.resolve("© Tuan\n\n{iso}", values: full)
        #expect(resolved == "© Tuan\n\nISO 400")
    }

    /// Dropping a token mid-segment must not leave the double space behind.
    @Test func removingAMidSegmentTokenSquashesTheGap() {
        let resolved = OverlayTokenResolver.resolve(
            "{camera} {lens} handheld",
            values: OverlayTokenValues(camera: "Canon EOS R6")
        )
        #expect(resolved == "Canon EOS R6 handheld")
    }

    @Test func containsKnownTokenIgnoresUnknownBraces() {
        #expect(!OverlayTokenResolver.containsKnownToken("{foo} bar"))
        #expect(OverlayTokenResolver.containsKnownToken("{foo} {iso}"))
    }

    // MARK: Values from the indexed row

    /// The row the app already indexed, with the raw tags deliberately messier
    /// than their normalized counterparts.
    private static func metadata(
        camera: String? = "Canon EOS R6",
        lens: String? = "RF 85mm F1.2 L USM"
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: "asset-1",
            creationDate: 1_784_000_000,
            modificationDate: nil,
            mediaType: 1,
            cameraManufacturer: "Canon",
            cameraModel: "Canon EOS R6 Body",
            normalizedCameraModel: camera,
            normalizedCameraManufacturer: "Canon",
            lensManufacturer: nil,
            lensModel: "RF85mm F1.2 L USM",
            normalizedLensModel: lens,
            originalFilename: "IMG_1234.CR3",
            iso: 400,
            aperture: 1.2,
            shutterSpeedSeconds: 1.0 / 500,
            shutterSpeedDisplay: nil,
            focalLength: 85,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6_000,
            height: 4_000,
            fileSize: nil,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: 0,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    @Test func valuesComeFromTheNormalizedRowNotTheRawTags() {
        let values = OverlayTokenValues(
            metadata: Self.metadata(),
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(values.camera == "Canon EOS R6")
        #expect(values.lens == "RF 85mm F1.2 L USM")
        #expect(values.focal == "85mm")
        #expect(values.aperture == "f/1.2")
        #expect(values.shutter == "1/500")
        #expect(values.iso == "ISO 400")
        #expect(values.filename == "IMG_1234.CR3")
        #expect(values.date != nil)
    }

    @Test func valuesFromNoMetadataAreAllEmpty() {
        #expect(OverlayTokenValues(metadata: nil) == .empty)
    }

    /// A row can hold a normalized value that is nothing but whitespace, which
    /// would otherwise render as a token that "resolved" to a blank.
    @Test func aWhitespaceOnlyValueCountsAsMissing() {
        let values = OverlayTokenValues(metadata: Self.metadata(camera: "   "))
        #expect(values.camera == nil)
    }

    /// An un-normalized row still says something useful, so the raw tag is used
    /// rather than dropping the token.
    @Test func aMissingNormalizedValueFallsBackToTheRawTag() {
        let values = OverlayTokenValues(metadata: Self.metadata(lens: nil))
        #expect(values.lens == "RF85mm F1.2 L USM")
    }
}
