import CoreGraphics
import CoreImage
import Foundation
@testable import ShotDexKit
import Testing
@testable import ShotDex

/// The Watermark screen's state (FS-05.04 §4–5), without a screen.
@MainActor
struct WatermarkModelTests {
    struct Stores {
        let defaults: UserDefaults
        let presets: SignaturePresetStore
        let settings: WatermarkSettingsStore
    }

    static func stores(presets list: [SignaturePreset]) throws -> Stores {
        let suite = "WatermarkModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let presets = SignaturePresetStore(defaults: defaults, images: OverlayImageStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        ))
        for preset in list.reversed() { presets.upsert(preset) }
        return Stores(defaults: defaults, presets: presets, settings: WatermarkSettingsStore(defaults: defaults))
    }

    static func page(_ id: String, size: CGSize = CGSize(width: 2048, height: 1365)) -> WatermarkPreviewPage {
        WatermarkPreviewPage(id: id, filename: "\(id).JPG", exportSize: size, tokens: OverlayTokenValues(camera: "ILCE-7M4")) { nil }
    }

    /// AC-2's number: on a 402×320 preview of photo A, the block's centre is
    /// within 1pt of where the 2048px export puts it, scaled down.
    @Test func previewCentreMatchesExport() throws {
        let stamp = WatermarkStamp(preset: WatermarkFixture.credit(logo: nil), placement: WatermarkFixture.placementW)
            .resolved(with: OverlayTokenValues(camera: "ILCE-7M4"))
        let export = CGSize(width: 2048, height: 1365)
        let exportFrame = try #require(PhotoRenderService.watermarkFrame(stamp, imageSize: export))
        let display = CGSize(width: 402, height: 320)
        // The preview picture: Resize renders the photo at 2,000px, so a
        // 2048 export previews at 2000×1333.
        let preview = CGSize(width: 2000, height: 1333)
        let centre = try #require(WatermarkModel.previewBoxCentre(stamp, imageSize: preview, displaySize: display))
        let scale = min(display.width / export.width, display.height / export.height)
        let expected = CGPoint(
            x: (display.width - export.width * scale) / 2 + exportFrame.box.midX * scale,
            y: (display.height - export.height * scale) / 2 + exportFrame.box.midY * scale
        )
        #expect(abs(centre.x - expected.x) <= 1, "\(centre) vs \(expected)")
        #expect(abs(centre.y - expected.y) <= 1, "\(centre) vs \(expected)")
    }

    /// Size reads in pixels of the photo previewed; a step is 1% of its short
    /// edge; typed pixels come back as a fraction.
    @Test func sizeStepsInPixelsOfThePreviewedPhoto() throws {
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try Self.stores(presets: [credit])
        stores.settings.update { $0.presetID = credit.id; $0.isEnabled = true; $0.placement = WatermarkFixture.placementW }
        let model = WatermarkModel(settings: stores.settings, presets: stores.presets, pages: [Self.page("a")], formTitle: "Resize")
        #expect(model.sizePixels == 55)
        model.stepSize(by: 1)
        #expect(model.sizePixels == 68)
        model.setSizePixels(100)
        #expect(abs(model.sizeFraction - 100.0 / 1365) < 0.0001)
        model.setSizePixels(10_000)
        #expect(model.sizeFraction == 0.25)
    }

    /// Switching on with nothing chosen picks the newest preset; choosing
    /// another preset starts it at its own size.
    @Test func turningOnPicksTheNewestPreset() throws {
        let older = SignaturePreset(name: "Studio", createdAt: Date(timeIntervalSince1970: 1), layers: [.text()])
        var credit = WatermarkFixture.credit(logo: nil)
        credit.createdAt = Date(timeIntervalSince1970: 2)
        let stores = try Self.stores(presets: [credit, older])
        let model = WatermarkModel(settings: stores.settings, presets: stores.presets, pages: [Self.page("a")], formTitle: "Resize")
        #expect(!model.isEnabled)
        model.setEnabled(true)
        #expect(model.selectedPreset?.name == "Credit")
        model.stepSize(by: 2)
        #expect(stores.settings.settings.placement.size != nil)
        model.choose(older)
        #expect(stores.settings.settings.placement.size == nil)
        #expect(model.isEnabled)
    }
}

/// The remembered configuration (FS-05.04 §5): one for every form.
@MainActor
struct WatermarkSettingsStoreTests {
    /// What Resize sets, the next form reads — the store is the same
    /// settings, whichever form opens it.
    @Test func remembersAcrossForms() throws {
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit])
        let resize = WatermarkModel(settings: stores.settings, presets: stores.presets, pages: [WatermarkModelTests.page("a")], formTitle: "Resize")
        resize.choose(credit)
        resize.setAnchor(.topLeft)
        resize.setMargin(0.05)
        resize.setOpacity(0.6)

        // A later launch, another form.
        let reopened = WatermarkSettingsStore(defaults: stores.defaults)
        let export = WatermarkModel(settings: reopened, presets: stores.presets, pages: [WatermarkModelTests.page("b")], formTitle: "Export")
        #expect(export.isEnabled)
        #expect(export.selectedPreset?.id == credit.id)
        #expect(export.placement.anchor == .topLeft)
        #expect(abs(export.placement.margin - 0.05) < 0.0001)
        #expect(abs(export.placement.opacity - 0.6) < 0.0001)
        #expect(reopened.formStamp(in: stores.presets.presets)?.presetID == credit.id)
    }

    /// Share With Watermark when Settings is Off (FS-05.04 §4): the preset
    /// last used on a form, else the newest; Settings stays Off.
    @Test func shareWithUsesLastFormPresetElseNewest() throws {
        let older = SignaturePreset(name: "Studio", createdAt: Date(timeIntervalSince1970: 1), layers: [.text()])
        var credit = WatermarkFixture.credit(logo: nil)
        credit.createdAt = Date(timeIntervalSince1970: 2)
        let stores = try WatermarkModelTests.stores(presets: [credit, older])
        let context = ShareWatermarkContext(
            settings: stores.settings, presets: stores.presets, libraryQueries: nil, editing: nil, imageExists: { _ in true }
        )
        #expect(context.preset(override: nil) == nil)
        #expect(context.preset(override: true)?.name == "Credit", "no form used yet: the newest")
        stores.settings.update { $0.presetID = older.id }
        #expect(context.preset(override: true)?.name == "Studio", "the one last used on a form")
        #expect(stores.settings.sharingPresetID == nil, "Settings stays Off")
        stores.settings.setSharingPreset(credit.id)
        #expect(context.preset(override: false) == nil)
        #expect(context.preset(override: nil)?.name == "Credit")
    }

    /// A preset deleted since reads as Off — never another preset.
    @Test func aDeletedPresetIsOff() throws {
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit, SignaturePreset(name: "Studio", createdAt: Date(), layers: [.text()])])
        stores.settings.update { $0.presetID = credit.id; $0.isEnabled = true }
        stores.presets.delete(id: credit.id)
        #expect(stores.settings.formStamp(in: stores.presets.presets) == nil)
        #expect(stores.settings.formPreset(in: stores.presets.presets) == nil)
    }

    @Test func sharingIsItsOwnSetting() throws {
        let stores = try WatermarkModelTests.stores(presets: [])
        let id = UUID()
        stores.settings.setSharingPreset(id)
        #expect(WatermarkSettingsStore(defaults: stores.defaults).sharingPresetID == id)
        stores.settings.setSharingPreset(nil)
        #expect(WatermarkSettingsStore(defaults: stores.defaults).sharingPresetID == nil)
        #expect(stores.settings.settings == WatermarkSettings())
    }

    /// AC-12: Credit, top left, Margin 5%, Opacity 60% set in Resize — the
    /// Export to Files sheet reads the same: the row says Credit, the screen
    /// opens there, switched on. Unmodified Original hides the row and
    /// leaves the choice alone.
    @Test func resizeThenExportSheetSeeTheSame() throws {
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit])
        let resize = WatermarkModel(
            settings: stores.settings, presets: stores.presets,
            pages: [WatermarkModelTests.page("a")], formTitle: "Resize", imageExists: { _ in true }
        )
        resize.choose(credit)
        resize.setAnchor(.topLeft)
        resize.setMargin(0.05)
        resize.setOpacity(0.6)

        let context = ShareWatermarkContext(
            settings: WatermarkSettingsStore(defaults: stores.defaults), presets: stores.presets,
            libraryQueries: nil, editing: nil, imageExists: { _ in true }
        )
        let sheet = FileExportModel(
            assetIds: ["b"], selection: .init(photoCount: 1), presets: ResizePreset.builtIns,
            settingsStore: FileExportSettingsStore(defaults: stores.defaults), watermarkContext: context
        )
        #expect(sheet.showsWatermark)
        #expect(sheet.watermarkRowValue == "Credit")
        let template = try #require(sheet.watermarkTemplate)
        #expect(template.placement.anchor == .topLeft)
        #expect(abs(template.placement.margin - 0.05) < 0.0001)
        #expect(abs(template.placement.opacity - 0.6) < 0.0001)

        let screen = WatermarkModel(
            settings: context.settings, presets: stores.presets,
            pages: [WatermarkModelTests.page("b")], formTitle: "Export", imageExists: { _ in true }
        )
        #expect(screen.isEnabled && screen.selectedPreset?.id == credit.id && screen.placement.anchor == .topLeft)

        sheet.mode = .unmodifiedOriginal
        #expect(!sheet.showsWatermark)
        #expect(context.settings.settings.isEnabled, "the remembered choice stays for the next Current Version")
    }

    /// The Export to Files seam: the photo's stamp rides on the render, and
    /// a photo whose edit already carries the preset gets none.
    @Test func exportStampingSetsThePhotosStamp() async throws {
        let template = WatermarkStamp(preset: WatermarkFixture.credit(logo: nil), placement: WatermarkFixture.placementW)
        let watermark = ShareWatermark(
            template: template, tokens: ["a": OverlayTokenValues(camera: "X-T5")], alreadyStamped: ["b"]
        )
        let stamping = WatermarkExportStamping(watermark: watermark)
        let result = PhotoRenderResult(
            image: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10)),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, properties: [:]
        )
        func item(_ id: String) -> FileExportItem {
            FileExportItem(id: id, filename: "\(id).JPG", captureDate: Date(), kind: .photo, files: [])
        }
        let a = try await stamping.stamp(result, for: item("a"))
        #expect(a.watermark?.layers.first?.text == "© Nguyen An · X-T5")
        let b = try await stamping.stamp(result, for: item("b"))
        #expect(b.watermark == nil)
    }
}
