import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 through Resize's batch, with no library behind it: what each
/// photo is stamped with, and what the summary says.
@MainActor
@Suite(.serialized) struct ResizeWatermarkTests {
    final class Library {
        var stamps: [String: WatermarkStamp?] = [:]
        var created: [String] = []
        var deleted: [String] = []
    }

    struct Batch {
        let controller: CompressionController
        let library: Library
        let presets: SignaturePresetStore
        let watermark: WatermarkSettingsStore
    }

    /// A Resize of `photos` with preset Credit (text only) and configuration
    /// W remembered and on; `metadata` gives each photo's indexed row.
    func resize(_ photos: [OriginalItem], metadata: [String: PhotoMetadata], enabled: Bool = true) throws -> Batch {
        let suite = "ResizeWatermarkTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let presets = SignaturePresetStore(defaults: defaults, images: OverlayImageStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        ))
        let credit = WatermarkFixture.credit(logo: nil)
        presets.upsert(credit)
        let watermark = WatermarkSettingsStore(defaults: defaults)
        watermark.update {
            $0.presetID = credit.id
            $0.isEnabled = enabled
            $0.placement = WatermarkFixture.placementW
        }
        let library = Library()
        let operations = ResizeOperations(
            compress: { photo, _, stamp in
                library.stamps[photo.id] = stamp
                library.created.append("copy-\(photo.id)")
                return PhotoSaveResult(assetID: "copy-\(photo.id)", format: .jpeg, fellBackToJPEG: false)
            },
            deleteOriginals: { library.deleted += $0 },
            removeCreated: { _ in }
        )
        let controller = CompressionController(
            photos: photos,
            operations: operations,
            fetcher: FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher()),
            watermarkSettings: watermark,
            signaturePresets: presets,
            // What the app passes: the indexed row, through the same values
            // the editor resolves `{camera}` from.
            tokenValues: { OverlayTokenValues(metadata: metadata[$0]) }
        )
        return Batch(controller: controller, library: library, presets: presets, watermark: watermark)
    }

    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(40)) }
        #expect(condition())
    }

    /// An indexed row as the composer writes it: the model through
    /// `CameraNormalizer`, the make dropped from it (FS-05.04 §3).
    static func row(_ id: String, make: String, model: String, lens: String? = nil) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: 1_790_000_000, modificationDate: nil, mediaType: 1,
            cameraManufacturer: make, cameraModel: model,
            normalizedCameraModel: CameraNormalizer.normalizeModel(model, manufacturer: make),
            normalizedCameraManufacturer: CameraNormalizer.normalizeManufacturer(make),
            lensManufacturer: nil, lensModel: lens, normalizedLensModel: lens,
            originalFilename: "IMG_\(id).JPG", iso: 400, aperture: 2.8, shutterSpeedSeconds: 1.0 / 250,
            shutterSpeedDisplay: nil, focalLength: 50, focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil, sensorFormat: nil, cropFactor: nil,
            width: 60, height: 40, fileSize: nil, latitude: nil, longitude: nil, isFavorite: false,
            indexedAt: 0, exifStatus: ExifStatus.indexed.rawValue
        )
    }

    /// AC-3: three photos from three cameras, configuration W — each file's
    /// stamp reads its own camera, the model without the make.
    @Test func tokensPerPhoto() async throws {
        let photos = ["sony", "fuji", "iphone"].map { OriginalItem.test($0) }
        let batch = try resize(photos, metadata: [
            "sony": Self.row("sony", make: "SONY", model: "ILCE-7M4"),
            "fuji": Self.row("fuji", make: "FUJIFILM", model: "X-T5"),
            "iphone": Self.row("iphone", make: "Apple", model: "iPhone 17 Pro"),
        ])
        batch.controller.startExport()
        try await until { batch.controller.didFinish }
        func text(_ id: String) -> String? { batch.library.stamps[id]??.layers.first?.text }
        #expect(text("sony") == "© Nguyen An · ILCE-7M4")
        #expect(text("fuji") == "© Nguyen An · X-T5")
        #expect(text("iphone") == "© Nguyen An · iPhone 17 Pro")
        #expect(batch.controller.watermarkTally.stamped == 3)
        #expect(batch.controller.finishedCleanly)
    }

    /// A preset that is only `{lens}` on a photo with no lens: the photo is
    /// saved without a stamp, and the summary names it.
    @Test func allTokensEmptyGoesUnstampedAndNamed() async throws {
        let photos = [OriginalItem.test("a"), OriginalItem.test("b")]
        let batch = try resize(photos, metadata: [
            "a": Self.row("a", make: "SONY", model: "ILCE-7M4", lens: "FE 50mm F1.2 GM"),
            "b": Self.row("b", make: "SONY", model: "ILCE-7M4"),
        ])
        var lensOnly = try #require(batch.presets.presets.first)
        lensOnly.layers[0].text = "{lens}"
        batch.presets.upsert(lensOnly)
        batch.controller.startExport()
        try await until { batch.controller.didFinish }
        #expect(batch.library.stamps["a"]??.layers.first?.text == "FE 50mm F1.2 GM")
        #expect(batch.library.stamps["b"] == .some(nil))
        #expect(batch.library.created.count == 2)
        #expect(batch.controller.watermarkTally.nothingToStamp == ["IMG_b.JPG"])
        #expect(!batch.controller.finishedCleanly, "the summary has to name it")
    }

    /// Off: nothing stamped, nothing to report.
    @Test func offStampsNothing() async throws {
        let batch = try resize([OriginalItem.test("a")], metadata: [:], enabled: false)
        batch.controller.startExport()
        try await until { batch.controller.didFinish }
        #expect(batch.library.stamps["a"] == .some(nil))
        #expect(batch.controller.watermarkTally == WatermarkTally())
    }
}
