import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b AC-15, AC-18: Collage and Video Studio ask once before taking
/// in RAWs this iOS build can't read — Convert to JPEG · Skip These N · Cancel.
struct UnsupportedRAWGateTests {
    static let batch = ["j1", "raw", "j2", "j3"]

    @Test func asksOnlyWhenSomethingIsUnreadable() {
        #expect(!UnsupportedRAWGate(ids: Self.batch, unreadableSet: []).asks)
        let gate = UnsupportedRAWGate(ids: Self.batch, unreadableSet: ["raw", "elsewhere"])
        #expect(gate.asks)
        #expect(gate.unreadable == ["raw"])
    }

    /// Convert keeps all four, Skip three, Cancel none.
    @Test func answers() {
        let gate = UnsupportedRAWGate(ids: Self.batch, unreadableSet: ["raw"])
        #expect(gate.ids(after: .convertToJPEG) == Self.batch)
        #expect(gate.ids(after: .skip) == ["j1", "j2", "j3"])
        #expect(gate.ids(after: .cancel) == nil)
    }

    @Test func wording() {
        let one = UnsupportedRAWGate(ids: Self.batch, unreadableSet: ["raw"], smallestPreview: PixelSize(width: 1616, height: 1080))
        #expect(one.title == "1 RAW photo can't be read on this iOS")
        #expect(one.message == "Convert it to JPEG first? ShotDex uses the JPEG preview inside the RAW (1616 × 1080).")
        #expect(one.convertTitle == "Convert to JPEG")
        #expect(one.skipTitle == "Skip These 1")
        let two = UnsupportedRAWGate(ids: ["a", "b", "c"], unreadableSet: ["a", "b"])
        #expect(two.title == "2 RAW photos can't be read on this iOS")
        #expect(two.message == "Convert them to JPEG first? ShotDex uses the JPEG preview inside the RAW.")
        #expect(two.skipTitle == "Skip These 2")
    }

    /// Convert to JPEG is the camera's own preview at its own size, read
    /// from the original — on a RAF the decoder refuses.
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.fuji), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func embeddedPreviewOfAnUnreadableRAW() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raf = try #require(try RAWFixtures.unsupportedCamera(in: folder))
        let image = try #require(EmbeddedRAWPreview.image(at: raf))
        #expect(image.width == 4416 && image.height == 2944)
        let capped = try #require(EmbeddedRAWPreview.image(at: raf, maxPixelSize: 1200))
        #expect(max(capped.width, capped.height) == 1200)
    }

    /// Collage: every way in asks, and a converted cell is drawn from the
    /// preview on the canvas and in the export, with nothing written first.
    @Test func collageAsksAtEveryDoor() throws {
        for path in [
            "ShotDex/Features/Library/LibraryScreen.swift", "ShotDex/Features/Albums/AlbumDetailScreen.swift",
            "ShotDex/Features/Albums/SmartAlbumDetailScreen.swift", "ShotDex/Features/Collage/CollageScreen.swift",
        ] {
            let code = try AssetMetadataCarryOverTests.codeLines(of: path).joined(separator: "\n")
            #expect(code.contains("UnsupportedRAWBatchPrompt.resolve("), "\(path) adds to a collage without asking")
        }
        let model = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Collage/CollageEditorModel.swift").joined(separator: "\n")
        #expect(model.contains("case .asset(let asset) where embeddedPreviewIds.contains(asset.localIdentifier):"))
        #expect(model.contains("if let asset = photo.asset, embeddedPreviewIds.contains(id) {"))
        let preview = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Data/Sources/EmbeddedRAWPreview.swift").joined(separator: "\n")
        #expect(!preview.contains("PHAssetCreationRequest"))
    }

    /// AC-18: five photos, two RAWs iOS can't read, Skip These 2 → three
    /// clips, none from a preview.
    @Test func videoStudioSkipLeavesThree() {
        let gate = UnsupportedRAWGate(ids: ["p1", "raw1", "p2", "raw2", "p3"], unreadableSet: ["raw1", "raw2"])
        #expect(gate.skipTitle == "Skip These 2")
        #expect(gate.ids(after: .skip) == ["p1", "p2", "p3"])
    }

    @Test func videoStudioAsksAtEveryDoor() throws {
        for path in [
            "ShotDex/Features/Library/LibraryScreen.swift", "ShotDex/Features/Albums/AlbumDetailScreen.swift",
            "ShotDex/Features/Albums/SmartAlbumDetailScreen.swift", "ShotDex/Features/Shared/PhotoListScreen.swift",
            // The door inside the studio is its Media panel (FS-12.09 §2),
            // which replaced the system picker the screen used to open.
            "ShotDex/Features/VideoStudio/VideoMediaPanel.swift",
        ] {
            let code = try AssetMetadataCarryOverTests.codeLines(of: path).joined(separator: "\n")
            #expect(code.contains("UnsupportedRAWBatchPrompt.resolve("), "\(path) opens Video Studio without asking")
        }
        let store = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Data/Sources/VideoFrameCompositor.swift").joined(separator: "\n")
        #expect(store.contains("if isEmbeddedPreview {"))
    }
}

