import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §6 / FS-03.07c AC-4, AC-5: a name already in the folder, or
/// twice in the batch.
extension FileExportPlanTests {
    /// AC-4: the folder holds `img_0001.jpg`; two photos of the batch are both
    /// `IMG_0001` (two cameras) — Keep Both writes `IMG_0001 (2).jpg` and
    /// `IMG_0001 (3).jpg`, and the old file is untouched.
    @Test func keepBothNumbersAgainstFolderAndBatch() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let old = fixture.destination.appendingPathComponent("img_0001.jpg")
        try Data("older export".utf8).write(to: old)
        let before = try ExportFixture.sha(old)
        let a = try fixture.file("a", "IMG_0001.JPG", role: .photo, data: ExportFixture.randomData(20_000))
        let b = try fixture.file("b", "IMG_0001.JPG", role: .photo, data: ExportFixture.randomData(20_000))
        let items = [
            FileExportItem(id: "a", filename: "IMG_0001.JPG", captureDate: ExportFixture.date(minutes: 1), camera: "X-T5", kind: .photo, files: [a]),
            FileExportItem(id: "b", filename: "IMG_0001.JPG", captureDate: ExportFixture.date(minutes: 2), camera: "EOS R6", kind: .photo, files: [b]),
        ]
        let plan = try fixture.plan(items, mode: .unmodifiedOriginal, renderExtension: "jpg")

        #expect(plan.entries.map { $0.outputs[0].name } == ["IMG_0001 (2).JPG", "IMG_0001 (3).JPG"])
        _ = await fixture.runner().run(FileExportJob(plan: plan, mode: .unmodifiedOriginal))

        #expect(fixture.names() == ["IMG_0001 (2).JPG", "IMG_0001 (3).JPG", "img_0001.jpg"])
        #expect(try ExportFixture.sha(old) == before)
        // The upload's rule is the same one, and still holds.
        #expect(ServerUploadPath.nextFreeName(for: "IMG_0001.jpg", existing: ["img_0001.jpg"]) == "IMG_0001 (2).jpg")
    }

    /// Replace never writes over a file the run itself just wrote: the
    /// batch's second `IMG_0001` is numbered; only the folder's file is
    /// replaced.
    @Test func replaceStillNumbersTheBatchItself() throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        try Data("old".utf8).write(to: fixture.destination.appendingPathComponent("IMG_0001.jpg"))
        let items = ["a", "b"].map { id in
            FileExportItem(id: id, filename: "IMG_0001.HEIC", captureDate: ExportFixture.date(minutes: id == "a" ? 1 : 2),
                           kind: .photo, files: [FileExportSourceFile(key: id, filename: "IMG_0001.HEIC", role: .photo)])
        }
        let plan = try fixture.plan(items, mode: .currentVersion, policy: .replace)

        #expect(plan.entries.map { $0.outputs[0].name } == ["IMG_0001.jpg", "IMG_0001 (2).jpg"])
        #expect(plan.entries.map { $0.outputs[0].replaces } == [true, false])
        #expect(plan.replaceCount == 1)
    }

    // MARK: AC-5

    /// 20 photos, 12 of whose names the folder already holds.
    @MainActor
    private func replaceSetup(_ fixture: ExportFixture, policy: FileExportConflictPolicy) throws -> FileExportModel {
        var items: [FileExportItem] = []
        for index in 1...20 {
            let name = String(format: "IMG_%04d.JPG", index)
            let file = try fixture.file("p\(index)", name, role: .photo, data: Data("new \(index)".utf8))
            items.append(FileExportItem(id: "p\(index)", filename: name, captureDate: ExportFixture.date(minutes: index),
                                        kind: .photo, files: [file]))
            if index <= 12 { try Data("old \(index)".utf8).write(to: fixture.destination.appendingPathComponent(name)) }
        }
        let defaults = try #require(UserDefaults(suiteName: "FileExportConflict-\(UUID().uuidString)"))
        let folders = ExportFolderStore(defaults: defaults)
        try folders.remember(fixture.destination)
        let store = FileExportSettingsStore(defaults: defaults)
        var settings = FileExportSettings()
        settings.mode = .unmodifiedOriginal
        settings.conflictPolicy = policy
        store.save(settings)
        let loaded = items
        return FileExportModel(
            assetIds: items.map(\.id), selection: .init(photoCount: 20), presets: ResizePreset.builtIns,
            settingsStore: store, folders: folders,
            environment: FileExportEnvironment(source: fixture.source, rendering: KitExportRenderer(), items: { _ in loaded })
        )
    }

    @MainActor
    private func waitFor(_ model: FileExportModel, _ done: (FileExportModel.Stage) -> Bool) async {
        for _ in 0..<3_000 where !done(model.stage) { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func contents(_ fixture: ExportFixture, _ index: Int) throws -> String {
        String(decoding: try Data(contentsOf: fixture.destination.appendingPathComponent(String(format: "IMG_%04d.JPG", index))), as: UTF8.self)
    }

    /// Replace asks once — *Replace 12 files in “Exports”?* — before the
    /// first byte; Cancel there changes nothing.
    @Test @MainActor func replaceAsksOnceBeforeFirstByte() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let model = try replaceSetup(fixture, policy: .replace)

        model.start()
        await waitFor(model) { $0 != .planning }

        #expect(model.stage == .confirmingReplace(12))
        #expect(ExportCopy.replaceTitle(12, folder: "Exports") == "Replace 12 files in “Exports”?")
        #expect(fixture.names().count == 12)
        #expect(fixture.source.copies.isEmpty)
    }

    @Test @MainActor func cancelAtReplaceChangesNothing() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let model = try replaceSetup(fixture, policy: .replace)
        model.start()
        await waitFor(model) { $0 != .planning }

        model.cancelReplace()

        #expect(model.stage == .choosing)
        #expect(fixture.names().count == 12)
        #expect(try contents(fixture, 1) == "old 1")
    }

    /// Replace confirmed: 20 files, the 12 old ones carry the new content —
    /// each swapped only after its new file was whole.
    @Test @MainActor func replaceSwapsAfterPartIsComplete() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let model = try replaceSetup(fixture, policy: .replace)
        model.start()
        await waitFor(model) { $0 != .planning }

        model.confirmReplace()
        await waitFor(model) { $0 == .finished }

        #expect(fixture.names().count == 20)
        #expect(try contents(fixture, 1) == "new 1")
        #expect(try contents(fixture, 12) == "new 12")
        #expect(!fixture.names().contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// Skip: 8 new files, the 12 old ones untouched, and the summary says
    /// *12 skipped — already in the folder*.
    @Test @MainActor func skipLeavesExisting() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let model = try replaceSetup(fixture, policy: .skip)

        model.start()
        await waitFor(model) { $0 == .finished }

        #expect(fixture.names().count == 20)
        #expect(try contents(fixture, 1) == "old 1")
        #expect(try contents(fixture, 13) == "new 13")
        #expect(model.report?.writtenCount == 8)
        let summary = FileExportSummary(plan: model.plan, report: model.report, preflight: nil, folder: model.folders.current)
        #expect(summary.detail.contains("12 skipped — already in the folder"))
        #expect(summary.headline == "Exported 8 photos to “Exports”.")
    }
}
