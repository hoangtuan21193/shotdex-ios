import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §3, §3a / FS-03.07c AC-1, AC-16: Export… sits under Resize,
/// the sheet remembers what the spec says — never Metadata, never Version —
/// and Size starts at Original.
@Suite @MainActor struct FileExportSettingsTests {
    static let client = ResizePreset(name: "Client 3000", kind: .longEdge, longEdge: 3_000, quality: 0.9, format: .jpeg)

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "FileExportSettingsTests-\(UUID().uuidString)"))
    }

    private func model(_ defaults: UserDefaults, metadata: MetadataLevel = .noLocation) -> FileExportModel {
        FileExportModel(
            assetIds: ["a"],
            selection: .init(photoCount: 1, editedCount: 1),
            presets: ResizePreset.builtIns + [Self.client],
            settingsStore: FileExportSettingsStore(defaults: defaults),
            metadataDefault: metadata
        )
    }

    @Test func remembersWhatSpecSaysAndNotMetadataOrVersion() throws {
        let defaults = try defaults()
        let first = model(defaults)
        #expect(first.settings == FileExportSettings())
        #expect(first.metadata == .noLocation)
        #expect(first.version == .edited)

        first.settings.dateFolders = true
        first.choosePreset(Self.client.id)
        first.settings.nameTemplate = FileNameTemplate.dateCameraNumber.pattern
        first.settings.conflictPolicy = .skip
        first.settings.includesLivePhotoVideo = false
        first.mode = .unmodifiedOriginal
        first.metadata = .all
        first.version = .original

        let second = model(defaults, metadata: .noMetadata)
        #expect(second.settings.dateFolders)
        #expect(second.mode == .unmodifiedOriginal)
        #expect(second.preset.name == "Client 3000")
        // A preset of the user's own brings its format and quality, as Resize.
        #expect(second.settings.format == .jpeg)
        #expect(second.settings.quality == 0.9)
        #expect(second.template == .dateCameraNumber)
        #expect(second.settings.conflictPolicy == .skip)
        #expect(!second.settings.includesLivePhotoVideo)
        // Metadata starts at the Settings level, Version at Edited.
        #expect(second.metadata == .noMetadata)
        #expect(second.version == .edited)
    }

    /// A preset deleted since last time is Original; unreadable settings are
    /// the defaults, not a crash.
    @Test func deletedPresetAndBadDataFallBack() throws {
        let defaults = try defaults()
        var settings = FileExportSettings()
        settings.presetId = UUID()
        FileExportSettingsStore(defaults: defaults).save(settings)
        #expect(model(defaults).preset.id == ResizePreset.original.id)

        defaults.set(Data("{\"mode\":\"bogus\",\"dateFolders\":true}".utf8), forKey: SettingsKeys.fileExportSettings)
        let loaded = FileExportSettingsStore(defaults: defaults).load()
        #expect(loaded.mode == .currentVersion)
        #expect(loaded.dateFolders)
    }

    /// AC-16: a fresh install opens at Size Original, the Resize presets in
    /// Resize's order after it; a choice is remembered; Original fills the
    /// gap a deleted preset leaves.
    @Test func sizeStartsAtOriginal() throws {
        let defaults = try defaults()
        let first = model(defaults)
        #expect(first.preset.id == ResizePreset.original.id)
        #expect(first.preset.name == "Original")
        #expect(first.presets.map(\.name) == ["Original", "4K", "2048 px", "1080 px", "Client 3000"])
        #expect(first.preset.kind == .original)

        first.choosePreset(ResizePreset.twoK.id)
        #expect(model(defaults).preset.name == "2048 px")
    }

    @Test func deletedPresetFallsBackToOriginal() throws {
        let defaults = try defaults()
        model(defaults).choosePreset(Self.client.id)
        let withoutIt = FileExportModel(
            assetIds: ["a"], selection: .init(photoCount: 1), presets: ResizePreset.builtIns,
            settingsStore: FileExportSettingsStore(defaults: defaults)
        )
        #expect(withoutIt.preset.id == ResizePreset.original.id)
    }

    /// AC-1: Export… is right under Resize in the album's ⋯, with its glyph;
    /// server folders don't offer it (their photos are files already).
    @Test func menuRowSitsUnderResize() {
        let menu = PhotoCommand.albumSelectionMenu
        #expect(menu.firstIndex(of: .export) == menu.firstIndex(of: .resize).map { $0 + 1 })
        #expect(PhotoCommand.export.systemImage == "square.and.arrow.up.on.square")
        #expect(PhotoCommand.export.title == "Export…")
        #expect(!PhotoCommand.serverSelectionMenu.contains(.export))
    }

    /// The Version row shows only for Current Version with an edited photo;
    /// Live Photo Video only for Unmodified Original.
    @Test func rowsFollowTheMode() throws {
        let model = model(try defaults())
        #expect(model.showsVersion && model.showsRenderRows && !model.showsLivePhotoVideo)
        model.mode = .unmodifiedOriginal
        #expect(!model.showsVersion && !model.showsRenderRows && model.showsLivePhotoVideo)
        #expect(model.summaryLines.last == ExportCopy.originalsAsTheyAre)
        // No folder yet: Export dims.
        #expect(!model.canExport)
    }
}
