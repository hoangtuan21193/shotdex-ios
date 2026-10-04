import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-03.07b §9 / FS-03.07c AC-12: room is checked before the first byte.
@Suite struct FileExportSpaceEstimateTests {
    private func item(_ id: String, bytes: Int64, width: Int = 6_000, height: Int = 4_000) -> FileExportItem {
        FileExportItem(id: id, filename: "\(id).JPG", captureDate: ExportFixture.date(), kind: .photo,
                       files: [FileExportSourceFile(key: id, filename: "\(id).JPG", role: .photo, byteCount: bytes)],
                       pixelWidth: width, pixelHeight: height)
    }

    private func plan(_ items: [FileExportItem], mode: FileExportMode) -> FileExportPlan {
        FileExportPlan.make(items: items, mode: mode, template: .originalName, policy: .keepBoth, dateFolders: false,
                            includesLivePhotoVideo: true, renderExtension: { _ in "jpg" }, existing: [:])
    }

    /// Unmodified Original: the originals' bytes — 40 × 30 MB = 1.2 GB.
    @Test func unmodifiedSumsOriginals() {
        let items = (1...40).map { item("p\($0)", bytes: 30_000_000) }
        #expect(FileExportSpaceEstimate.neededBytes(plan(items, mode: .unmodifiedOriginal), preset: .original) == 1_200_000_000)
    }

    /// Current Version at 2048 on 6000×4000: the share of pixels kept.
    @Test func currentScalesByPixelRatio() {
        let one = item("a", bytes: 24_000_000)
        let needed = FileExportSpaceEstimate.neededBytes(plan([one], mode: .currentVersion), preset: .twoK)
        // 2048×1365 of 6000×4000 ≈ 11.6 %.
        #expect(needed > 2_700_000 && needed < 2_900_000)
        #expect(FileExportSpaceEstimate.neededBytes(plan([one], mode: .currentVersion), preset: .original) == 24_000_000)
    }

    @Test func unknownFreeSkipsTheCheck() {
        #expect(FileExportSpaceEstimate.check(needed: 1_200_000_000, free: nil) == nil)
        #expect(FileExportSpaceEstimate.check(needed: 1_200_000_000, free: 2_000_000_000) == nil)
        #expect(FileExportSpaceEstimate.check(needed: 1_200_000_000, free: 300_000_000) == .notEnoughSpace(needed: 1_200_000_000, free: 300_000_000))
        #expect(ExportCopy.notEnoughSpace("Exports", needed: 1_200_000_000, free: 300_000_000)
                == "Not enough space in “Exports” — needs 1.2 GB, 300 MB free.")
    }
}

/// A folder that reports little room.
struct SmallFolderWriter: ExportDestinationWriter {
    let inner: LocalFolderWriter
    let free: Int64?

    func existingNames(in folder: String) async throws -> Set<String> { try await inner.existingNames(in: folder) }
    func freeBytes() async -> Int64? { free }
    func sweepLeftoverParts(in folder: String) async { await inner.sweepLeftoverParts(in: folder) }
    func write(name: String, in folder: String, replacing: Bool, produce: @Sendable (URL) async throws -> Void) async throws -> ExportWrittenFile {
        try await inner.write(name: name, in: folder, replacing: replacing, produce: produce)
    }
}

extension FileExportRunnerTests {
    /// AC-12: 40 originals, 1.2 GB, into a folder with 300 MB free — the
    /// sheet says so before the first byte and the folder gets nothing.
    @Test @MainActor func notEnoughSpaceWritesNothing() async throws {
        let fixture = ExportFixture()
        defer { fixture.cleanUp() }
        let items = try (1...40).map { index in
            var file = try fixture.file("p\(index)", "IMG_\(index).JPG", role: .photo, data: Data("x".utf8))
            file.byteCount = 30_000_000
            return FileExportItem(id: "p\(index)", filename: "IMG_\(index).JPG", captureDate: ExportFixture.date(minutes: index),
                                  kind: .photo, files: [file])
        }
        let defaults = try #require(UserDefaults(suiteName: "FileExportSpace-\(UUID().uuidString)"))
        let folders = ExportFolderStore(defaults: defaults)
        try folders.remember(fixture.destination)
        let store = FileExportSettingsStore(defaults: defaults)
        var settings = FileExportSettings()
        settings.mode = .unmodifiedOriginal
        store.save(settings)
        let model = FileExportModel(
            assetIds: items.map(\.id), selection: .init(photoCount: 40), presets: ResizePreset.builtIns,
            settingsStore: store, folders: folders,
            environment: FileExportEnvironment(
                source: fixture.source, rendering: KitExportRenderer(), items: { _ in items },
                makeWriter: { SmallFolderWriter(inner: LocalFolderWriter(root: $0), free: 300_000_000) }
            )
        )

        model.start()
        for _ in 0..<3_000 where !model.spaceAlert { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(model.spaceAlert)
        #expect(model.stage == .choosing)
        #expect(model.preflightFailure == .notEnoughSpace(needed: 1_200_000_000, free: 300_000_000))
        #expect(fixture.names().isEmpty)
        #expect(fixture.source.copies.isEmpty)
        #expect(model.summaryLines.contains { $0.hasPrefix("300 MB free on ") })
    }
}
