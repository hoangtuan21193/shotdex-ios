import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b AC-6: a RAW whose EXIF names no camera. The message falls back
/// to the file's extension, and the tile carries no mark — not knowing the
/// camera is not knowing it is unsupported.
@MainActor
struct UnsupportedRAWNoCameraTests {
    typealias F = RAWVerdictFixtures

    @Test func messageNamesTheExtension() {
        let message = UnsupportedRAWMessage.make(cameraName: nil, filename: "DSC00042.arw", iOSVersion: "27.0")
        #expect(message.text == "iOS 27.0 doesn't support RAW files like this .ARW yet. Convert the file to DNG with Adobe DNG Converter, or wait for an iOS update that adds this camera.")
        #expect(UnsupportedRAWMessage.make(cameraName: "  ", filename: "x.ARW", iOSVersion: "27.0").subject == .fileExtension("ARW"))
    }

    /// The decoder refuses everything, yet ARWs with no Make/Model are
    /// neither judged nor marked.
    @Test func noCameraIsNeverMarked() async throws {
        let blank = F.rows("x", 3, ext: "ARW", make: nil, model: nil)
            + [F.row("y1", file: "y1.ARW", make: "SONY", model: "  ")]
        let probe = FakeRAWProbe(local: ["x1", "x2", "x3", "y1"])
        let index = UnsupportedRAWIndex(store: RAWVerdictStore(database: try F.database(blank)), probe: probe, release: F.release)
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds.isEmpty)
        #expect(probe.asked.isEmpty)
        #expect(try index.store.verdicts(build: F.release.build).isEmpty)
        #expect(index.message(for: "x1") == nil)
    }
}
