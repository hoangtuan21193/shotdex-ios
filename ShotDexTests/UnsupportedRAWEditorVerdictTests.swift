import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b AC-10: the editor's own attempt settles a camera the pass
/// could not judge, and its tiles are marked without reopening the app.
@MainActor
struct UnsupportedRAWEditorVerdictTests {
    typealias F = RAWVerdictFixtures

    func index(_ rows: [PhotoMetadata]) throws -> UnsupportedRAWIndex {
        UnsupportedRAWIndex(store: RAWVerdictStore(database: try F.database(rows)), probe: FakeRAWProbe(), release: F.release)
    }

    /// Six ARWs only in iCloud: unknown, nothing marked; the editor is
    /// refused on one → all six marked.
    @Test func refusalMarksAnUnknownCamera() async throws {
        let index = try index(F.rows("s", 6, ext: "ARW", make: "SONY", model: "ILCE-7M5"))
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds.isEmpty)
        await index.recordEditorResult(assetId: "s3", decoded: false)
        #expect(index.assetIds == Set((1...6).map { "s\($0)" }))
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        #expect(try index.store.verdict(for: camera, build: F.release.build) == .unreadable)
    }

    /// One odd file of a camera the decoder reads changes nothing.
    @Test func readableCameraStaysReadable() async throws {
        let index = UnsupportedRAWIndex(
            store: RAWVerdictStore(database: try F.database(F.rows("n", 3, ext: "NEF", make: "NIKON CORPORATION", model: "NIKON Z 6_2"))),
            probe: FakeRAWProbe(models: ["Nikon Z 6 2"]), release: F.release
        )
        index.runPass()
        await index.waitForPass()
        await index.recordEditorResult(assetId: "n2", decoded: false)
        #expect(index.assetIds.isEmpty)
    }

    /// The editor opening the file settles unknown as readable.
    @Test func openingSettlesUnknownAsReadable() async throws {
        let index = try index(F.rows("s", 2, ext: "ARW", make: "SONY", model: "ILCE-7M5"))
        index.runPass()
        await index.waitForPass()
        await index.recordEditorResult(assetId: "s1", decoded: true)
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        #expect(try index.store.verdict(for: camera, build: F.release.build) == .readable)
        #expect(index.assetIds.isEmpty)
    }

    @Test func editorReportsEveryRAWOpening() throws {
        let screen = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Editing/PhotoEditorScreen.swift").joined(separator: "\n")
        #expect(screen.contains("recordEditorResult(assetId: assetId, decoded: false)"))
        #expect(screen.contains("recordEditorResult(assetId: assetId, decoded: true)"))
    }
}
