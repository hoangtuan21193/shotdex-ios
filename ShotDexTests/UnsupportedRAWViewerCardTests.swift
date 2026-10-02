import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b AC-17: the viewer's glyph opens a card naming the camera and
/// the iOS version, saying the preview stays viewable; its target is 44pt.
struct UnsupportedRAWViewerCardTests {
    @Test func cardNamesCameraVersionAndWhatStillWorks() {
        let card = UnsupportedRAWMessage.make(cameraName: "Nikon Z5II", filename: "DSC_1.NEF", iOSVersion: "27.0").viewerCard
        #expect(card == "Nikon Z5II — iOS 27.0 can't read RAW files from this camera yet. You can still view the preview, but you can't edit the RAW.")
        #expect(UnsupportedRAWMessage.make(cameraName: nil, filename: "a.ARW", iOSVersion: "27.0").viewerCard
            .hasSuffix("You can still view the preview, but you can't edit the RAW."))
    }

    @Test func glyphIsItsOwn44PointButton() throws {
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift").joined(separator: "\n")
        #expect(viewer.contains(".frame(width: 44, height: 44)"))
        #expect(viewer.contains("unsupportedRAWGlyph(raw)"))
        #expect(viewer.contains(".presentationCompactAdaptation(.popover)"))
    }
}
