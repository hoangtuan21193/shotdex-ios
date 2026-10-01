import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 §4 — the share sheet's header line and the app's two rows.
struct ShareBatchPlanTests {

    /// AC-7: at No Location the header says so and the two rows are the two
    /// other levels; the level in force has no row.
    @Test func rowsAndSubtitle() {
        let plan = ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 0)
        #expect(plan.subtitle == .locationRemoved)
        #expect(plan.rows == [.all, .noMetadata])
        #expect(ShareLevelRow.title(for: .all) == "Share With Location")
        #expect(ShareLevelRow.title(for: .noMetadata) == "Share Without Metadata")

        let all = ShareBatchPlan(level: .all, photoCount: 3, videoCount: 0)
        #expect(all.subtitle == .allMetadata)
        #expect(all.rows == [.noLocation, .noMetadata])
        #expect(ShareLevelRow.title(for: .noLocation) == "Share Without Location")

        let none = ShareBatchPlan(level: .noMetadata, photoCount: 2, videoCount: 0)
        #expect(none.subtitle == .metadataRemoved)
        #expect(none.rows == [.all, .noLocation])
        for plan in [plan, all, none] { #expect(plan.rows.count == 2) }
    }

    /// Video goes as it is at every level, so a share of only videos has no
    /// level to change.
    @Test func videosOnlyHaveNoRows() {
        #expect(ShareBatchPlan(level: .noLocation, photoCount: 0, videoCount: 2).rows.isEmpty)
    }

    /// AC-20 (and the Settings half of AC-2): a row changes this share only.
    /// Nothing in the share path writes the Settings level — the only
    /// writers are the Settings picker and the one-time carry-over of the
    /// old switch — and a row's choice reaches the gather as an argument.
    @Test func oneShotOverrideKeepsSettings() throws {
        let root = AssetMetadataCarryOverTests.repository.appendingPathComponent("ShotDex")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var writers: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("SettingsKeys.shareMetadataLevel") { writers.append(file.lastPathComponent) }
        }
        #expect(Set(writers) == ["SettingsKeys.swift", "SettingsScreen.swift"], "\(writers)")

        let sheet = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Shared/PhotoShareSheet.swift")
            .joined(separator: "\n")
        #expect(sheet.contains("let again = await regather(level)"))
        #expect(!sheet.contains("UserDefaults"))
    }
}
