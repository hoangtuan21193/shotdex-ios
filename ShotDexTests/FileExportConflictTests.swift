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
}
