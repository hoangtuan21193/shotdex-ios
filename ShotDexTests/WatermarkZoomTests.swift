import CoreGraphics
import Foundation
@testable import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 §4a / AC-17, AC-18: Before and After shows the bare picture and
/// ends when the stamp changes; Zoom centres on the stamp, covers the frame,
/// re-reads the page sharper within its cap and survives a page change.
@MainActor
struct WatermarkZoomTests {
    static func picture(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A model of 6 pages, photo A's export (2048×1365) previewed from a
    /// 1200×800 picture, Credit on at configuration W.
    private func model(detail: (@MainActor (CGFloat) async -> CGImage?)? = nil) throws -> (WatermarkModel, WatermarkSettingsStore) {
        let credit = WatermarkFixture.credit(logo: nil)
        let stores = try WatermarkModelTests.stores(presets: [credit])
        stores.settings.update { $0.presetID = credit.id; $0.isEnabled = true; $0.placement = WatermarkFixture.placementW }
        let base = Self.picture(width: 1_200, height: 800)
        let pages = (0..<6).map { index in
            WatermarkPreviewPage(
                id: "p\(index)", filename: "P\(index).JPG", exportSize: CGSize(width: 2_048, height: 1_365),
                tokens: OverlayTokenValues(camera: "ILCE-7M4"), load: { base }, loadDetail: detail
            )
        }
        let model = WatermarkModel(settings: stores.settings, presets: stores.presets, pages: pages, formTitle: "Resize",
                                   imageExists: { _ in true })
        return (model, stores.settings)
    }

    private func waitForStamp(_ model: WatermarkModel, page: Int = 0) async throws {
        let id = model.pages[page].id
        for _ in 0..<200 where model.stamped[id] == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.stamped[id] != nil)
    }

    /// AC-17: on, the preview is the bare picture; off, the stamp is back;
    /// the remembered configuration never moves.
    @Test func beforeShowsTheBarePicture() async throws {
        let (model, settings) = try model()
        let page = model.pages[0]
        await model.load(page)
        try await waitForStamp(model)
        let before = settings.settings

        model.showsBefore = true
        #expect(model.image(for: page) === model.bases[page.id])
        model.showsBefore = false
        #expect(model.image(for: page) === model.stamped[page.id])
        #expect(model.image(for: page) !== model.bases[page.id])
        #expect(settings.settings == before)
    }

    /// AC-17: moving any control of the stamp ends Before and After — the
    /// user changed the stamp to see it.
    @Test func changingTheStampEndsBefore() async throws {
        let (model, settings) = try model()
        model.showsBefore = true
        model.setOpacity(0.6)
        #expect(!model.showsBefore)
        #expect(abs(settings.settings.placement.opacity - 0.6) < 0.0001)
        for change in [{ model.setAnchor(.topLeft) }, { model.setMargin(0.05) }, { model.stepSize(by: 1) }, { model.setEnabled(false) }] {
            model.showsBefore = true
            change()
            #expect(!model.showsBefore)
        }
    }

    /// AC-18: at 400% the stamp's centre sits inside the frame and the
    /// picture covers it — no black edge — on the 960×640 iPad preview.
    @Test func centresOnTheStampAndCoversTheFrame() async throws {
        let (model, _) = try model()
        let page = model.pages[0]
        await model.load(page)
        let display = CGSize(width: 960, height: 640)
        let image = CGSize(width: 1_200, height: 800)
        let focus = try #require(model.zoomFocus(for: page, displaySize: display))
        #expect(focus.x > display.width * 0.8 && focus.y > display.height * 0.8, "bottom right: \(focus)")

        for zoom in [WatermarkZoom.double, .quadruple] {
            let offset = WatermarkZoom.offset(focus: focus, imageSize: image, displaySize: display, scale: zoom.scale)
            // Where the stamp lands on screen.
            let x = display.width / 2 + (focus.x - display.width / 2) * zoom.scale + offset.width
            let y = display.height / 2 + (focus.y - display.height / 2) * zoom.scale + offset.height
            #expect((0...display.width).contains(x) && (0...display.height).contains(y), "\(zoom): \(x), \(y)")
            // The zoomed picture still covers the frame.
            let half = CGSize(width: display.width * zoom.scale / 2, height: display.height * zoom.scale / 2)
            #expect(abs(offset.width) <= half.width - display.width / 2 + 0.01)
            #expect(abs(offset.height) <= half.height - display.height / 2 + 0.01)
        }
        // A pan past the edge is held at the edge.
        let far = WatermarkZoom.offset(focus: focus, pan: CGSize(width: -10_000, height: 0), imageSize: image, displaySize: display, scale: 4)
        #expect(abs(far.width + (960 * 4 - 960) / 2) < 0.01, "\(far)")
        // Stamp off: zoom on the middle.
        #expect(WatermarkZoom.offset(focus: nil, imageSize: image, displaySize: display, scale: 4) == .zero)
        #expect(WatermarkZoom.fit.title == "Fit" && WatermarkZoom.double.title == "200%" && WatermarkZoom.quadruple.title == "400%")
    }

    /// AC-18: the sharper re-read is never bigger than the file written, the
    /// screen at that level, or 4096 px.
    @Test func detailEdgeIsCapped() {
        let display = CGSize(width: 960, height: 640)
        #expect(WatermarkZoom.detailLongEdge(exportSize: CGSize(width: 2_048, height: 1_365), displaySize: display, scale: 4, screenScale: 2) == 2_048)
        #expect(WatermarkZoom.detailLongEdge(exportSize: CGSize(width: 6_000, height: 4_000), displaySize: display, scale: 4, screenScale: 2) == 4_096)
        #expect(WatermarkZoom.detailLongEdge(exportSize: CGSize(width: 6_000, height: 4_000), displaySize: CGSize(width: 402, height: 320), scale: 2, screenScale: 3) == 2_412)
    }

    /// AC-18: zoomed, the page is re-read at the asked edge and stamped on
    /// that; another page keeps the level with the pan reset; Fit lets the
    /// big picture go.
    @Test func pageChangeKeepsTheLevel() async throws {
        var asked: [CGFloat] = []
        let (model, _) = try model(detail: { edge in
            asked.append(edge)
            return Self.picture(width: Int(edge), height: Int(edge * 2 / 3))
        })
        let first = model.pages[0]
        await model.load(first)
        model.setZoom(.quadruple)
        await model.loadDetail(for: first, longEdge: 2_048)
        #expect(asked == [2_048])
        #expect(model.image(for: first)?.width == 2_048 || model.details[first.id]?.width == 2_048)
        model.pan = CGSize(width: 40, height: 0)

        model.currentIndex = 4
        #expect(model.zoom == .quadruple)
        #expect(model.pan == .zero)
        #expect(model.details.isEmpty, "one big page at a time")
        let fifth = model.pages[4]
        await model.load(fifth)
        await model.loadDetail(for: fifth, longEdge: 2_048)
        #expect(model.details[fifth.id]?.width == 2_048)

        model.setZoom(.fit)
        #expect(model.details.isEmpty)
        // At Fit nothing is re-read.
        await model.loadDetail(for: fifth, longEdge: 2_048)
        #expect(asked.count == 2)
    }
}
