import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 §5: what a form does with a preset that is gone, half gone, or
/// never was.
@MainActor
@Suite(.serialized) struct WatermarkAvailabilityTests {
    /// AC-13: the last preset used was Logo, and its image file has been
    /// deleted from the app's folder — the row reads Off and the chip says
    /// Missing file and cannot be chosen.
    @Test func missingLogoFileIsOffAndNotSelectable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkAvailability-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = OverlayImageStore(directory: folder)
        let logoFile = try WatermarkFixture.storeLogo(in: images)
        var logo = SignaturePreset(name: "Logo", createdAt: Date(), layers: [.image(id: logoFile, assetIdentifier: nil)])
        logo.sourceAspect = 1.5
        let stores = try WatermarkModelTests.stores(presets: [logo, WatermarkFixture.credit(logo: nil)])
        stores.settings.update { $0.presetID = logo.id; $0.isEnabled = true }
        let exists: (UUID) -> Bool = { FileManager.default.fileExists(atPath: images.url(for: $0).path) }

        let before = CompressionController(
            photos: [OriginalItem.test("a")],
            operations: ResizeOperations(compress: { _, _, _ in throw CancellationError() }, deleteOriginals: { _ in }, removeCreated: { _ in }),
            fetcher: FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher()),
            watermarkSettings: stores.settings, signaturePresets: stores.presets, imageExists: exists
        )
        #expect(before.watermarkRowValue == "Logo")

        // The file goes, as a reinstall or a cleanup would take it.
        try FileManager.default.removeItem(at: images.url(for: logoFile))
        #expect(WatermarkAvailability.of(logo, imageExists: exists) == .missingFile)
        #expect(before.watermarkRowValue == WatermarkCopy.off())
        #expect(before.watermarkTemplate == nil)
        #expect(!before.isDeleteOriginalsLocked, "nothing is stamped, so nothing is locked")

        let model = WatermarkModel(
            settings: stores.settings, presets: stores.presets,
            pages: [WatermarkModelTests.page("a")], formTitle: "Resize", imageExists: exists
        )
        #expect(!model.isEnabled)
        model.choose(logo)
        #expect(model.selectedPreset == nil, "a Missing file chip cannot be chosen")
        #expect(WatermarkScreen.presetLabel(logo, model.availability(of: logo)) == "Logo, Missing file")
        // Switching on falls to a preset that can be stamped, never Logo.
        model.setEnabled(true)
        #expect(model.selectedPreset?.name == "Credit")
    }

    /// A typeface that is gone falls back and still stamps: Unavailable,
    /// selectable.
    @Test func lostFontIsUnavailableButSelectable() {
        var caption = PhotoOverlay.text()
        caption.text = "© Nguyen An"
        caption.fontPostScriptName = "NoSuchFace-Bold"
        caption.fontFamilyName = "No Such Family"
        let preset = SignaturePreset(name: "Studio", createdAt: Date(), layers: [caption])
        let availability = WatermarkAvailability.of(preset, imageExists: { _ in true })
        #expect(availability == .fontUnavailable)
        #expect(availability.isSelectable)
        #expect(WatermarkCopy.chipDetail(preset, availability: availability, locale: Locale(identifier: "en")) == "Unavailable")
        #expect(WatermarkAvailability.of(WatermarkFixture.credit(logo: nil), imageExists: { _ in true }) == .available)
    }

    /// A preset deleted since is Off — never another preset.
    @Test func deletedPresetIsOff() throws {
        let credit = WatermarkFixture.credit(logo: nil)
        let studio = SignaturePreset(name: "Studio", createdAt: Date(), layers: [.text()])
        let stores = try WatermarkModelTests.stores(presets: [credit, studio])
        stores.settings.update { $0.presetID = credit.id; $0.isEnabled = true }
        stores.presets.delete(id: credit.id)
        let controller = CompressionController(
            photos: [OriginalItem.test("a")],
            operations: ResizeOperations(compress: { _, _, _ in throw CancellationError() }, deleteOriginals: { _ in }, removeCreated: { _ in }),
            fetcher: FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher()),
            watermarkSettings: stores.settings, signaturePresets: stores.presets
        )
        #expect(controller.watermarkRowValue == WatermarkCopy.off())
    }

    /// No preset yet: the row reads None and is dimmed; the screen explains.
    @Test func noPresetIsNone() throws {
        let stores = try WatermarkModelTests.stores(presets: [])
        let controller = CompressionController(
            photos: [OriginalItem.test("a")],
            operations: ResizeOperations(compress: { _, _, _ in throw CancellationError() }, deleteOriginals: { _ in }, removeCreated: { _ in }),
            fetcher: FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher()),
            watermarkSettings: stores.settings, signaturePresets: stores.presets
        )
        #expect(controller.watermarkRowValue == WatermarkCopy.none())
        #expect(!controller.hasWatermarkPresets)
        #expect(WatermarkCopy.noWatermarksYet(locale: Locale(identifier: "en")) == "No watermarks yet")
    }
}
