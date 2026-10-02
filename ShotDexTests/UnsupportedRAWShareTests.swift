import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.04b AC-8: Share Original of a RAW iOS can't read hands over the
/// original byte for byte; below All Metadata it goes through FS-08.06's RAW
/// question with Share as JPEG dimmed.
struct UnsupportedRAWShareTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rawshare-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func source(readable: Bool) -> ShareSource {
        var source = ShareSource(id: "dng", kind: .raw, filename: "DJI_0001.DNG", uniformType: "com.adobe.raw-image")
        source.isReadable = readable
        return source
    }

    @Test func unreadableRAWDimsShareAsJPEG() {
        let plan = ShareBatchPlan(sources: [Self.source(readable: false)], level: .noLocation)
        #expect(plan.asksAboutRAW)
        #expect(!plan.offersJPEG)
        // A RAW the decoder reads keeps the JPEG choice.
        #expect(ShareBatchPlan(sources: [Self.source(readable: true)], level: .noLocation).offersJPEG)
        // All Metadata asks nothing: the file goes as it is.
        #expect(!ShareBatchPlan(sources: [Self.source(readable: false)], level: .all).asksAboutRAW)
    }

    /// The same byte count as the resource, at All Metadata and after Share
    /// RAW with Location — on a cut-off DNG the decoder refuses.
    @Test(.enabled(if: RAWFixtures.has(RAWFixtures.dji), "needs the RAW samples in ~/Library/Caches/ShotDexFixtures/raw/"))
    func originalLeavesByteForByte() async throws {
        let dng = try #require(try RAWFixtures.truncated(RAWFixtures.dji, bytes: 200_000, in: folder))
        let original = try Data(contentsOf: dng)
        let reader = LocalFileShareReader(files: ["dng": dng])
        for (level, choice) in [(MetadataLevel.all, RAWChoice.skip), (.noLocation, .shareRAWWithLocation)] {
            let out = try ShareExportPipeline.makeFolder(in: folder)
            var pipeline = ShareExportPipeline(reader: reader, folder: out, level: level)
            pipeline.rawChoice = choice
            let result = await pipeline.export([Self.source(readable: false)])
            #expect(result.failed.isEmpty)
            let file = try #require(result.files.first)
            #expect(file.lastPathComponent == "DJI_0001.DNG")
            #expect(try Data(contentsOf: file) == original)
        }
    }

    /// Every share entry passes what the index knows, and the alerts' Share
    /// Original names the photo itself.
    @Test func sharesCarryTheUnreadableSet() throws {
        let sheet = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Shared/PhotoShareSheet.swift").joined(separator: "\n")
        #expect(sheet.contains("if source.kind == .raw, unreadableRAW.contains(source.id) { source.isReadable = false }"))
        for path in [
            "ShotDex/App/AssetActionsCoordinator.swift", "ShotDex/Features/Library/LibraryScreen.swift",
            "ShotDex/Features/Albums/AlbumDetailScreen.swift", "ShotDex/Features/Albums/OnThisDayScreen.swift",
            "ShotDex/Features/Albums/SmartAlbumDetailScreen.swift", "ShotDex/Features/Library/PhotoDetailScreen.swift",
            "ShotDex/Features/Editing/PhotoEditorScreen.swift",
        ] {
            let code = try AssetMetadataCarryOverTests.codeLines(of: path).joined(separator: "\n")
            #expect(code.contains("unreadableRAW:"), "\(path) shares without the unreadable set")
        }
    }
}
