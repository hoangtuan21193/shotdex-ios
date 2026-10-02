import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.04b AC-7: a RAW-only DNG the decoder refuses says the file is at
/// fault, points at the latest DNG Converter, and offers Share Original · OK.
@MainActor
struct UnsupportedRAWDNGTests {
    static let text = "iOS 27.0 can't read this DNG file. Convert the original again with the latest Adobe DNG Converter, or share it to edit on a computer."

    @Test func dngMessageOffersShareOriginal() {
        // The camera's name is not the point for a DNG: the file is.
        let message = UnsupportedRAWMessage.make(cameraName: "DJI FC4382", filename: "DJI_0001.dng", iOSVersion: "27.0")
        #expect(message.text == Self.text)
        #expect(message.offersShareOriginal)
        let failure = EditorLoadFailure.unsupportedRAW(message)
        #expect(failure.offersShareOriginal)
        #expect(failure.message == Self.text)
        // A camera the decoder doesn't know has nothing to share for.
        #expect(!UnsupportedRAWMessage.make(cameraName: "Sony ILCE-7M5", filename: "a.ARW", iOSVersion: "27.0").offersShareOriginal)
    }

    /// A cut-off DNG of a camera the decoder reads: the editor's own refusal.
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.dji), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func cutOffDNGReadsAsTheDNGMessage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dng-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try #require(try RAWFixtures.truncated(RAWFixtures.dji, bytes: 200_000, in: folder))
        await #expect(throws: PhotoEditingError.unsupportedRAW) {
            try await PhotoRenderService().inspectSource(at: url)
        }
        let error = RAWFileCamera.error(for: url, filename: "DJI_0001.DNG", release: RAWVerdictFixtures.release)
        #expect(error.localizedDescription == Self.text)
    }

    /// Both alerts carry the button: the viewer's and the editor's.
    @Test func bothAlertsOfferIt() throws {
        let alert = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/UnsupportedRAWAlert.swift").joined(separator: "\n")
        #expect(alert.contains("if shown.offersShareOriginal, let shareOriginal {"))
        let editor = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift").joined(separator: "\n")
        #expect(editor.contains("if failure.offersShareOriginal, let shareOriginal {"))
        let viewer = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift").joined(separator: "\n")
        #expect(viewer.contains(".unsupportedRAWAlert($unsupportedRAWMessage, shareOriginal: shareCurrentOriginal)"))
    }
}
