import Foundation
import Testing
import ShotDexKit
@testable import ShotDex

/// The iPad inspector's Mac-style rows (FS-12.04b §4, AC-15; boards IL2,
/// IP2, IL3, IP3): the numbers the boards draw, kept in one place.
struct VideoDeskRowsTests {
    /// Label 96 · value 60 (4 from the slider) · row 44 · knob 28 · track
    /// 4; Volume's speaker 40 with a 28 disc, its label 84 at 56 from the
    /// column's edge; the Speed presets 36 tall.
    @Test func rowGeometryIsTheBoards() {
        #expect(DeskRowMetrics.labelWidth == 96)
        #expect(DeskRowMetrics.valueWidth == 60 && DeskRowMetrics.valueGap == 4)
        #expect(DeskRowMetrics.rowHeight == 44 && DeskRowMetrics.knob == 28 && DeskRowMetrics.track == 4)
        #expect(DeskRowMetrics.muteButton == 40 && DeskRowMetrics.muteDisc == 28)
        #expect(16 - DeskRowMetrics.muteGap + DeskRowMetrics.muteButton + DeskRowMetrics.muteGap == 56)
        #expect(DeskRowMetrics.volumeLabelWidth == 84)
        #expect(DeskRowMetrics.segmentedHeight == 36)
        #expect(DeskRowMetrics.labelSize == 17 && DeskRowMetrics.valueSize == 15)
        // In the 360 inspector: 16 + 96 + slider + 4 + 60 + 16 → a 168 slider.
        #expect(360 - 16 - DeskRowMetrics.labelWidth - DeskRowMetrics.valueGap - DeskRowMetrics.valueWidth - 16 == 168)
    }

    /// Speed's presets are the chips' four speeds, in order.
    @Test func speedPresetsAreFour() {
        #expect(VideoClipPanelSections.speedPresets == [0.5, 1, 2, 4])
    }

    /// The caption colours: White, Black and the board's four tints, each
    /// with its own spoken name; Custom Color follows them.
    @Test func swatchesAreTheBoards() {
        let hex = DeskSwatchRow.swatches.map { color in
            String(format: "#%02X%02X%02X", Int((color.red * 255).rounded()), Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
        }
        #expect(hex == ["#FFFFFF", "#000000", "#F2C94C", "#E8604C", "#4FA3E0", "#7BC47F"])
        let names = (0..<6).map(DeskSwatchRow.name)
        #expect(names == ["White", "Black", "Yellow", "Red", "Blue", "Green"])
    }
}
