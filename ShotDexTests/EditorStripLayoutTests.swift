import CoreGraphics
import Testing
@testable import ShotDex

struct EditorStripLayoutTests {

    /// FS-03.12 AC-4/AC-5: five text chips or fewer share the width; more scroll.
    /// Swatch strips always share it — Color Mix's nine (All + eight bands) included.
    @Test func shortTextStripsAndEverySwatchStripShareTheWidth() {
        #expect(EditorStripLayout.sharesWidth(itemCount: 4, kind: .text))
        #expect(EditorStripLayout.sharesWidth(itemCount: 5, kind: .text))
        #expect(!EditorStripLayout.sharesWidth(itemCount: 6, kind: .text))
        #expect(EditorStripLayout.sharesWidth(itemCount: 9, kind: .swatch))
    }

    /// On the narrowest phone (375pt) a four-chip strip still leaves each chip
    /// room for "Highlights" at 13pt, and nine swatches each get more than a 20pt
    /// swatch needs. Spacing sits on the DESIGN.md scale.
    @Test func equalWidthItemsFitTheNarrowestPhone() {
        let four = EditorStripLayout.equalItemWidth(itemCount: 4, in: 375)
        let expectedFour: CGFloat = (375 - 12 * 2 - 8 * 3) / 4
        #expect(abs(four - expectedFour) < 0.001)
        #expect(four > 75)
        let nine = EditorStripLayout.equalItemWidth(itemCount: 9, in: 375)
        #expect(nine > 30)
        #expect(EditorStripLayout.chipSpacing == 8)
        #expect(EditorStripLayout.horizontalInset == 12)
        #expect(EditorStripLayout.chipIconSpacing == 4)
        #expect(EditorStripLayout.equalItemWidth(itemCount: 0, in: 375) == 0)
    }
}
