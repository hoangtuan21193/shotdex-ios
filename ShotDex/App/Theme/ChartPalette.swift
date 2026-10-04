import SwiftUI
import UIKit

/// Chart colors for Swift Charts — replaces the framework default palette.
///
/// One series is drawn in the app accent alone: ordinary marks in a pale mix
/// of it, the mark that matters (the largest bucket) in the full accent, so a
/// chart answers "which one?" at a glance and never competes with the photos.
/// Several series (a donut, one line per camera) take `colors` in order — the
/// accent first, then hues checked for color-blind separation against the
/// light and dark chart surfaces.
enum ChartPalette {
    static let colors: [Color] = [
        dynamic(light: 0xC6730E, dark: 0xCF7F18),
        dynamic(light: 0x3D6FB6, dark: 0x5C88E0),
        dynamic(light: 0x1E9180, dark: 0x1F9C84),
        dynamic(light: 0x9A4FA0, dark: 0xB070C8),
        dynamic(light: 0x6F8A1E, dark: 0x7C962A),
        dynamic(light: 0xB83E8C, dark: 0xD35E98),
    ]

    /// Categorical color for the series or slice at `index`. Past the last
    /// hue every slice is one neutral grey — the tail reads as "other", never
    /// as a repeat of the first series.
    static func color(at index: Int) -> Color {
        index < colors.count ? colors[index] : Color(.systemGray)
    }

    /// `color(at:)` for the first `count` series, for a chart's style scale.
    static func range(count: Int) -> [Color] {
        (0..<max(count, 1)).map(color(at:))
    }

    /// Single series, the mark that matters: the full accent.
    static let emphasis = AppAccent.color

    /// Single series, every other mark: the accent at 38% (light) / 45% (dark).
    static let quiet = Color(UIColor { traits in
        AppAccent.uiColor.resolvedColor(with: traits)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.45 : 0.38)
    })

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
