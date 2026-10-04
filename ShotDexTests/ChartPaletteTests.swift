import SwiftUI
import Testing
@testable import ShotDex

struct ChartPaletteTests {
    @Test func leadSeriesIsTheAccentHue() {
        let lead = UIColor(ChartPalette.color(at: 0)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        lead.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(Int((red * 255).rounded()) == 0xC6)
        #expect(Int((green * 255).rounded()) == 0x73)
        #expect(Int((blue * 255).rounded()) == 0x0E)
    }

    @Test func tailSlicesAreGreyNotARepeat() {
        let count = ChartPalette.colors.count
        #expect(ChartPalette.color(at: count) == Color(.systemGray))
        #expect(ChartPalette.color(at: count + 5) == Color(.systemGray))
        #expect(ChartPalette.color(at: count) != ChartPalette.color(at: 0))
    }

    @Test func rangeCoversEverySeries() {
        #expect(ChartPalette.range(count: 8).count == 8)
        #expect(ChartPalette.range(count: 0).count == 1)
    }
}
