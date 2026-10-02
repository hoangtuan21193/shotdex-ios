import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-03.04b AC-4: once the verdict is in, Edit on such a photo answers from
/// the index — within a second, with no PhotoKit request (so nothing from
/// iCloud) and no "Downloading" spinner.
@MainActor
struct UnsupportedRAWGateTimingTests {
    typealias F = RAWVerdictFixtures

    @Test func answerComesFromTheIndexAlone() async throws {
        // A library-sized index: 8 unreadable ARWs among 6,000 HEICs.
        let rows = F.rows("s", 8, ext: "ARW", make: "SONY", model: "ILCE-7M5")
            + F.rows("h", 6_000, ext: "HEIC", make: "Apple", model: "iPhone 17 Pro")
        let probe = FakeRAWProbe(local: ["s1", "s2"])
        let index = UnsupportedRAWIndex(store: RAWVerdictStore(database: try F.database(rows)), probe: probe, release: F.release)
        index.runPass()
        await index.waitForPass()
        let asked = probe.asked
        let clock = ContinuousClock()
        var message: UnsupportedRAWMessage?
        let elapsed = clock.measure { message = index.message(for: "s5") }
        #expect(message != nil)
        #expect(elapsed < .seconds(1))
        // Answering asked the decoder (and so PhotoKit) nothing.
        #expect(probe.asked == asked)
    }

    /// The editor of a run, on such a photo: the failure without a load —
    /// no session, no download fraction, no spinner.
    @Test func editorFailsWithoutLoading() {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        let message = UnsupportedRAWMessage.make(cameraName: "Sony ILCE-7M5", filename: nil, iOSVersion: "27.0")
        controller.failWithoutLoading(.unsupportedRAW(message))
        #expect(controller.loadFailure == .unsupportedRAW(message))
        #expect(!controller.isLoading)
        #expect(controller.downloadFraction == nil)
        #expect(controller.loadedSource == nil)
    }

    /// The viewer's Edit asks the index before it sets the editor up.
    @Test func viewerAsksTheIndexFirst() throws {
        let screen = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Library/PhotoDetailScreen.swift")
            .joined(separator: "\n")
        let body = try #require(screen.range(of: "private func openEditor(for asset: PHAsset) {"))
        let rest = screen[body.upperBound...]
        let gate = try #require(rest.range(of: "unsupportedRAWIndex?.message(for: asset.localIdentifier)"))
        let open = try #require(rest.range(of: "editorTarget = PhotoDetailActionTarget("))
        #expect(gate.lowerBound < open.lowerBound)
        #expect(!screen.contains("editorTarget = PhotoDetailActionTarget(\n                                id: currentAsset"))
    }
}
