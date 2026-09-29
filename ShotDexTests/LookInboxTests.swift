import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

@MainActor
struct LookInboxTests {
    private func makeDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func lookFile(_ name: String, lut: LookFile.EmbeddedLUT? = nil) throws -> URL {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.3
        if lut != nil { recipe.lutID = "sender-side" }
        let data = try LookFileCodec.encode(LookPreset(name: name, recipe: recipe), lut: lut)
        let url = makeDirectory("sent").appendingPathComponent("\(name).shotdexlook")
        try data.write(to: url)
        return url
    }

    /// FS-03.14 AC-c7. A file opened while the app was not running is
    /// imported once — the launch's own drain finds nothing more — with the
    /// banner "Golden added to My Looks" · Undo, and the copy is gone.
    @Test func coldLaunchFileIsImportedOnce() async throws {
        let looks = LookPresetStore(directory: makeDirectory("looks"), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let banner = AppBannerModel()
        let inboxDirectory = makeDirectory("inbox")
        let inbox = LookInbox(looks: looks, luts: nil, banner: banner, directory: inboxDirectory)
        let sent = try lookFile("Golden")

        let report = try #require(await inbox.receive(sent))
        await inbox.drain()
        #expect(report.addedCount == 1)
        #expect(looks.presets.map(\.name) == ["Golden"])
        #expect(banner.current?.text == "Golden added to My Looks")
        #expect(banner.current?.actionTitle == "Undo")
        #expect(banner.current?.duration ?? .zero <= .seconds(4))
        #expect(inbox.pending.isEmpty, "the copy is deleted after the import")
        #expect(FileManager.default.fileExists(atPath: sent.path), "the sender's file is not ours to delete")
    }

    /// FS-03.14 AC-c8. "Teal Look" carrying the LUT "Teal": Undo on the
    /// banner takes back the look and the LUT, and the inbox copy is gone.
    @Test func undoRemovesTheWholeReceive() async throws {
        let looks = LookPresetStore(directory: makeDirectory("looks"), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let luts = ImportedLUTStore()
        let banner = AppBannerModel()
        let inbox = LookInbox(looks: looks, luts: luts, banner: banner, directory: makeDirectory("inbox"))
        let lutsBefore = luts.luts.count
        let cube = "TITLE \"Teal\"\nLUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
        let sent = try lookFile("Teal Look", lut: LookFile.EmbeddedLUT(name: "Teal", cube: cube))

        await inbox.receive(sent)
        #expect(looks.presets.map(\.name) == ["Teal Look"])
        #expect(luts.luts.count == lutsBefore + 1)
        #expect(looks.presets.first?.recipe.lutID == luts.luts.first { $0.displayName == "Teal" }?.id)
        #expect(banner.current?.actionTitle == "Undo")

        banner.performAction()
        #expect(looks.presets.isEmpty)
        #expect(luts.luts.count == lutsBefore)
        #expect(inbox.pending.isEmpty)
        #expect(banner.current == nil)
    }

    /// A copy left behind by a launch that ended mid-import is imported on
    /// the next launch's drain, and not again.
    @Test func leftoverCopyImportsOnNextLaunch() async throws {
        let looks = LookPresetStore(directory: makeDirectory("looks"), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let inboxDirectory = makeDirectory("inbox")
        let waiting = inboxDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try lookFile("Dune"), to: waiting.appendingPathComponent("Dune.shotdexlook"))

        let inbox = LookInbox(looks: looks, luts: nil, banner: AppBannerModel(), directory: inboxDirectory)
        await inbox.drain()
        await inbox.drain()
        #expect(looks.presets.map(\.name) == ["Dune"])
        #expect(inbox.pending.isEmpty)
    }

    /// Anything ≈ or ✕ turns the banner into a count with Details.
    @Test func mixedReceiveOffersDetails() {
        let report = PresetImportReport(entries: [
            .init(name: "Golden", status: .added, lines: []),
            .init(name: "Broken", status: .skipped, lines: []),
        ])
        let message = LookInbox.bannerMessage(for: report)
        #expect(message.text == "1 look added · 1 skipped")
        #expect(message.showsDetails)
        let again = LookInbox.bannerMessage(for: PresetImportReport(entries: [
            .init(name: "Harbour", status: .skipped, lines: [.init(kind: .skipped, text: "Already in My Looks")]),
        ]))
        #expect(again.text == "Harbour not added")
        #expect(again.showsDetails)
        #expect(PresetImportReport(entries: [.init(name: "A", status: .skipped, lines: [])]).header == "No looks added · 1 skipped")
    }
}
