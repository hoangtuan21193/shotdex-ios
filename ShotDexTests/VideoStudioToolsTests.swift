import CoreGraphics
import Foundation
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

/// FS-12.07 §2: the phone's top band.
struct VideoStudioPhoneBandTests {
    /// FS-12.07 AC-6: Back, Undo, Redo at x 16/56/96 and Video Settings,
    /// Export at 306/350 on 402pt, all 36pt — and none of them over the
    /// Dynamic Island's 138–264, on any phone width. (The board draws 10/350;
    /// 16 keeps the outer discs clear of the screen's rounded corner.)
    @Test func phoneTopBandLeavesTheIslandClear() {
        let expected: [VideoStudioMetrics.PhoneBandItem: CGFloat] = [
            .back: 16, .undo: 56, .redo: 96, .videoSettings: 306, .export: 350,
        ]
        for item in VideoStudioMetrics.PhoneBandItem.allCases {
            let frame = VideoStudioMetrics.phoneBandFrame(item, width: 402)
            #expect(frame.minX == expected[item])
            #expect(frame.size == CGSize(width: 36, height: 36))
        }
        #expect(VideoStudioMetrics.dynamicIslandSpan(width: 402) == 138...264)
        // Every phone with a Dynamic Island (the 375pt SE has none, and the
        // row there runs under nothing).
        for width in [CGFloat(393), 402, 440] {
            let island = VideoStudioMetrics.dynamicIslandSpan(width: width)
            for item in VideoStudioMetrics.PhoneBandItem.allCases {
                let frame = VideoStudioMetrics.phoneBandFrame(item, width: width)
                #expect(frame.maxX <= island.lowerBound || frame.minX >= island.upperBound, "\(item) on \(width)")
            }
        }
    }
}

/// FS-12.04 §3: which cells open a panel.
@MainActor
struct VideoStudioToolPanelTests {
    /// FS-12.04 AC-14 (model half): Music opens the in-frame Music panel —
    /// Video sound is its level, and no Master exists to show beside it.
    @Test func theMusicCellOpensTheMusicPanel() {
        #expect(VideoStudioToolbar.panel(for: .music) == .music)
        #expect(VideoStudioToolbar.panel(for: .look) == .look)
        #expect(VideoStudioToolbar.panel(for: .media) == nil)
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.music)
        #expect(model.activeToolPanel == .music)
        model.setVideoVolume(0.4)
        #expect(model.recipe.videoVolume == 0.4)
        // The recipe has no project-wide level other than Video sound.
        let written = String(decoding: (try? JSONEncoder().encode(model.recipe)) ?? Data(), as: UTF8.self)
        #expect(!written.contains("master"))
    }
}
