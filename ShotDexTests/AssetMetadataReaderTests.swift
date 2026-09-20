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
