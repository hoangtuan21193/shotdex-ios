import ImageIO
import Testing
@testable import ShotDex

/// `resourceHeadingText` is the composition rule behind the Info panel's
/// per-file headings ("RAW", "Paired Video · MOV") — pulled out of
/// `resourceHeading` so it can run without a live `PHAssetResource`, which
/// PhotoKit hands out only from `assetResources(for:)`.
@Suite struct AssetMetadataReaderResourceHeadingTests {
    @Test func aPlainPhotoHeadingIsJustTheFormat() {
        #expect(AssetMetadataReader.resourceHeadingText(kind: "Photo", fileExtension: "cr3") == "RAW")
        #expect(AssetMetadataReader.resourceHeadingText(kind: "Photo", fileExtension: "jpeg") == "JPG")
    }

    @Test func aNonPhotoKindKeepsBothTheKindAndTheFormat() {
        #expect(
            AssetMetadataReader.resourceHeadingText(kind: "Paired Video", fileExtension: "mov")
                == "Paired Video · MOV"
        )
        #expect(
            AssetMetadataReader.resourceHeadingText(kind: "Full-size Photo", fileExtension: "heic")
                == "Full-size Photo · HEIC"
        )
    }

    @Test func anUnrecognizedExtensionFallsBackToTheKindAlone() {
        // No extension at all: `FileTypeBadge.text` returns nil for an empty
        // string, so the heading has nothing to add and stays the bare kind —
        // even for `Photo`, which the recognized-format branch would otherwise
        // have collapsed to just the format.
        #expect(AssetMetadataReader.resourceHeadingText(kind: "Photo", fileExtension: "") == "Photo")
        #expect(AssetMetadataReader.resourceHeadingText(kind: "Adjustment Data", fileExtension: "") == "Adjustment Data")
    }

    @Test func anUnknownExtensionStillGetsAFormatLabel() {
        // `FileTypeBadge.text` never returns nil for a non-empty extension —
        // an unrecognized one still yields its own (truncated) uppercase name.
        #expect(AssetMetadataReader.resourceHeadingText(kind: "Photo", fileExtension: "xyz") == "XYZ")
    }
}

/// FS-02.07 AC-14: the file's own IPTC keywords and caption stay a read-only
/// row of *Rights & Description*, on every iOS — a Lightroom export reads
/// `Lightroom, test` exactly as before Photos keywords existed.
@Suite struct AssetMetadataReaderRightsTests {
    @Test func iptcKeywordsJoin() {
        let section = AssetMetadataReader.rightsSection(
            tiff: [:],
            iptc: [
                kCGImagePropertyIPTCKeywords as String: ["Lightroom", "test"],
                kCGImagePropertyIPTCCaptionAbstract as String: "Probe IPTC caption",
            ]
        )
        #expect(section.title == "Rights & Description")
        #expect(section.rows.first { $0.key == "Keywords" }?.value == "Lightroom, test")
        #expect(section.rows.first { $0.key == "Caption" }?.value == "Probe IPTC caption")
    }

    @Test func noRightsMeansNoRows() {
        #expect(AssetMetadataReader.rightsSection(tiff: [:], iptc: [:]).rows.isEmpty)
    }
}
