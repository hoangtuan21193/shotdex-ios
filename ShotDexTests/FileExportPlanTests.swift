import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §5–6: the names of a whole batch, worked out before the first
/// byte.
@Suite struct FileExportPlanTests {
    private func photo(_ id: String, _ name: String, day: Int = 20, minutes: Int, camera: String?, fixture: ExportFixture) throws -> FileExportItem {
        let file = try fixture.file(id, name, role: .photo, data: ExportFixture.image(width: 300, height: 200, gray: 0.5, gps: false))
        return FileExportItem(id: id, filename: name, captureDate: ExportFixture.date(day: day, minutes: minutes),
                              camera: camera, kind: .photo, files: [file], pixelWidth: 300, pixelHeight: 200)
    }

    /// AC-3: `{date}_{camera}_{sequence}` on photo A (X-T5, 17:05), an X-T5 frame
    /// at 17:06 and a screenshot of the next day — and the folder holds those
    /// three names after a Current Version JPEG export.
    @Test func dateCameraSeqDropsMissingTokens() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let items = [
            try photo("s", "IMG_0003.PNG", day: 21, minutes: 0, camera: nil, fixture: fixture),
            try photo("b", "DSCF1001.JPG", minutes: 6, camera: "X-T5", fixture: fixture),
            try photo("a", "DSCF1000.JPG", minutes: 5, camera: "X-T5", fixture: fixture),
        ]
        let plan = try fixture.plan(items, mode: .currentVersion, template: .dateCameraSequence)

        #expect(plan.entries.flatMap { $0.outputs.map(\.name) } == [
            "2026-09-20_X-T5_001.jpg", "2026-09-20_X-T5_002.jpg", "2026-09-21_003.jpg",
        ])

        let report = await fixture.runner().run(FileExportJob(plan: plan, mode: .currentVersion,
                                                              render: FileExportRenderOptions(format: .jpeg)))
        #expect(report.failed.isEmpty)
        #expect(fixture.names() == ["2026-09-20_X-T5_001.jpg", "2026-09-20_X-T5_002.jpg", "2026-09-21_003.jpg"])
    }

    /// The example line is the first photo of the batch in export order —
    /// capture date, then name — as the plan will name it.
    @Test @MainActor func exampleUsesFirstPhotoOfBatch() throws {
        var components = DateComponents(year: 2026, month: 9, day: 20, hour: 17, minute: 5, second: 12)
        components.timeZone = .current
        let shot = try #require(Calendar(identifier: .gregorian).date(from: components))
        let defaults = try #require(UserDefaults(suiteName: "FileExportPlanTests-\(UUID().uuidString)"))
        let model = FileExportModel(
            assetIds: ["a", "b"],
            selection: .init(photoCount: 3, first: FileNameValues(original: "DSCF1000", captureDate: shot, camera: "X-T5"),
                             firstExtension: "HEIC"),
            presets: ResizePreset.builtIns,
            settingsStore: FileExportSettingsStore(defaults: defaults),
            folders: ExportFolderStore(defaults: defaults)
        )
        model.chooseTemplate(.dateCameraSequence)
        model.settings.format = .jpeg
        #expect(model.exampleName == "2026-09-20_X-T5_001.jpg")
        // Typing into Custom changes it at once, and Custom takes the ✓.
        model.customTemplate = "{date}_Hoi-An_{sequence}"
        #expect(model.exampleName == "2026-09-20_Hoi-An_001.jpg")
        #expect(model.usesCustomTemplate)
        // Same as Original keeps a HEIC a HEIC.
        model.settings.format = .preserve
        #expect(model.exampleName == "2026-09-20_Hoi-An_001.heic")
        // Order: date, then name.
        let a = FileExportItem(id: "a", filename: "B.JPG", captureDate: shot, kind: .photo, files: [])
        let b = FileExportItem(id: "b", filename: "A.JPG", captureDate: shot, kind: .photo, files: [])
        let c = FileExportItem(id: "c", filename: "C.JPG", captureDate: shot.addingTimeInterval(-60), kind: .photo, files: [])
        #expect(FileExportPlan.ordered([a, b, c]).map(\.id) == ["c", "b", "a"])
    }
}
