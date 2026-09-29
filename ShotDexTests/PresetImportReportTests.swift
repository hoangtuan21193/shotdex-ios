import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct PresetImportReportTests {
    /// FS-03.14 AC-a7. Exposure +1.00 and an unknown crs:FutureSlider: the
    /// look is added with Exposure +1.00, the row is ≈, and the line names
    /// the tag.
    @Test func unknownTagsAreListedNotFatal() throws {
        let settings = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(
            #"crs:Exposure2012="+1.00" crs:FutureSlider="40""#
        ))
        let result = LightroomMapping.map(settings)
        #expect(result.recipe.adjustments[.exposure] == 1)
        #expect(result.lines == [PresetReportLine(kind: .changed, text: "Unknown setting FutureSlider — ignored")])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .addedWithChanges)
    }

    /// FS-03.14 AC-a6. Ten .xmp at once, one with broken XML: nine looks
    /// added in file order, one ✕ row named after the broken file, and
    /// "9 looks added · 1 skipped".
    @MainActor @Test func oneBrokenPresetOnlyLosesItself() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var urls: [URL] = []
        for index in 1...10 {
            let url = folder.appendingPathComponent("Preset \(index).xmp")
            let data = index == 7
                ? Data("<x:xmpmeta><rdf:RDF><unclosed></rdf:RDF>".utf8)
                : LightroomXMPReaderTests.preset(#"crs:Exposure2012="+0.\#(index)0""#)
            try data.write(to: url)
            urls.append(url)
        }
        let plan = try PresetImporter.read(urls)
        let store = LookPresetStore(
            directory: folder.appendingPathComponent("store"),
            defaults: UserDefaults(suiteName: "import-\(UUID().uuidString)")!
        )
        let report = PresetImporter.apply(plan, looks: store, luts: nil)
        #expect(report.header == "9 looks added · 1 skipped")
        #expect(store.presets.count == 9)
        #expect(store.presets.map(\.name).first == "Preset 1", "file order, first on top")
        #expect(store.presets.allSatisfy { $0.source == .imported })
        let broken = try #require(report.entries.first { $0.status == .skipped })
        #expect(broken.name == "Preset 7")
        #expect(broken.lines.first?.text == "The file is not valid XMP. Try exporting the preset from Lightroom again.")
        let kept = try #require(store.presets.first)
        #expect(store.originalPresetURL(for: kept) != nil, "the preset file is kept beside it")
    }
}
