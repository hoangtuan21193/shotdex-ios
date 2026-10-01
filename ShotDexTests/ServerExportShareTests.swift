import Foundation
import ImageIO
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 AC-22 — the Share destination of the server export sheet. The
/// render carries the photo's metadata (it is also what goes back to the
/// server and to Photos), so what leaves through the share sheet goes
/// through the share pipeline at the Settings level.
struct ServerExportShareTests {

    /// A render of `DSCF1000.JPG` — camera, exposure and GPS, as the
    /// renderer writes them with metadata on — shared at No Location: no
    /// GPS, Make and Model kept.
    @Test func noLocationRenderHasNoGPS() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = MetadataFixture.Options()
        options.xmp = false
        let render = folder.appendingPathComponent("DSCF1000.jpg")
        try MetadataFixture.encode(.jpeg, options: options).write(to: render)
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: render) != nil)

        let pipeline = ShareExportPipeline(
            reader: LocalFileShareReader(files: [render.path: render]),
            folder: try ShareExportPipeline.makeFolder(in: folder),
            level: .noLocation
        )
        let result = await pipeline.export([ShareSource(id: render.path, kind: .photo, filename: "DSCF1000.jpg")])
        let shared = try #require(result.files.first)
        #expect(MetadataFixture.dictionary(kCGImagePropertyGPSDictionary, of: shared) == nil)
        let tiff = try #require(MetadataFixture.dictionary(kCGImagePropertyTIFFDictionary, of: shared))
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == MetadataFixture.make)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == MetadataFixture.model)
    }

    /// The sheet hands its renders to the share pipeline — never straight
    /// to the share sheet — at the Settings level, so the rows and the
    /// header come with it.
    @Test func theSheetSharesThroughThePipeline() throws {
        let sheet = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/ServerImport/ServerExportSheet.swift")
            .joined(separator: "\n")
        #expect(sheet.contains("PhotoShareSheet.gather("))
        #expect(sheet.contains("level: .sharingDefault()"))
        #expect(!sheet.contains("PhotoShareSheet.present(items:"))
    }
}
