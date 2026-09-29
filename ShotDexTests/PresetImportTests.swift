import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct PresetImportTests {
    /// FS-03.14 AC-a11. 300 presets, Cancel at "Reading 120 of 300": the read
    /// stops there and nothing reaches My Looks — the stores are written only
    /// once the whole lot is read.
    @MainActor @Test func cancelAddsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try (1...300).map { index in
            let url = folder.appendingPathComponent("P\(index).xmp")
            try LightroomXMPReaderTests.preset(#"crs:Contrast2012="\#(index % 100)""#).write(to: url)
            return url
        }
        let store = LookPresetStore(directory: folder.appendingPathComponent("store"), defaults: UserDefaults(suiteName: "cancel-\(UUID().uuidString)")!)
        let before = store.presets

        let read = Task.detached { () throws -> Int in
            var reached = 0
            _ = try PresetImporter.read(urls) { done, _ in
                reached = done
                if done == 120 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return reached
        }
        await #expect(throws: PresetImporter.Cancelled.self) { try await read.value }
        #expect(store.presets == before)

        // The editor's model: Cancel closes the sheet and leaves the shelf.
        let model = LookExchangeModel(looks: store, luts: ImportedLUTStore())
        model.startImport(urls)
        #expect(model.isSheetPresented)
        model.cancelImport()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!model.isSheetPresented)
        #expect(store.presets == before)
    }
}
