import CoreGraphics
import Testing
@testable import ShotDex

/// The Video Studio's bottom row (FS-12.04 §2–3): five tools that add to the
/// timeline, plus Look, in one order everywhere.
@MainActor
struct VideoStudioToolsTests {
    /// FS-12.04 AC-1: the phone's row is Media · Text · Sticker · Music ·
    /// Look — and nothing that changes the whole video sits there any more.
    @Test func theBottomRowIsTheFiveAddToolsInOrder() {
        let model = VideoStudioModelFixture.model()
        let actions = VideoInspectorActions(
            onExport: {}, onBack: {}, onAddMedia: {}, onReplaceClip: {}, onAddText: {},
            onAddSticker: {}, onAddMusic: {}, onReplaceMusic: { _ in }, onEditText: { _ in }, onPickFont: {}
        )
        let row = VideoStudioToolbar(model: model, actions: actions)
        #expect(VideoStudioToolbar.tools(poolCarriesInserts: false) == [.media, .text, .sticker, .music, .look])
        #expect(row.commands.map(\.systemImage) == VideoAddTool.allCases.map(\.systemImage))
        #expect(row.commands.count == 5)
        // Ratio, Filter, Adjust, Color, Volume and Background are not tools.
        #expect(!row.commands.map(\.systemImage).contains("aspectratio"))
        #expect(!row.commands.map(\.systemImage).contains("speaker.wave.2"))
    }

    /// Five 72×52 cells across 402pt from a 6pt inset: x 9, 87, 165, 243, 321.
    @Test func theRowSpreadsFiveCellsOverTheWidth() {
        let xs = VideoStudioMetrics.toolCellXs(width: 402)
        #expect(xs.map { ($0 * 10).rounded() / 10 } == [9, 87, 165, 243, 321])
        #expect(VideoStudioMetrics.toolCellSize == CGSize(width: 72, height: 52))
    }

    /// Tapping Look opens its panel and lights the cell; tapping it again
    /// closes the panel and keeps what it changed.
    @Test func tappingTheOpenCellAgainClosesAndKeeps() {
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.look)
        #expect(model.activeToolPanel == .look)
        model.setFilterIntensity(0.5)
        model.toggleToolPanel(.look)
        #expect(model.activeToolPanel == nil)
        #expect(model.recipe.filterIntensity == 0.5)
    }
}
