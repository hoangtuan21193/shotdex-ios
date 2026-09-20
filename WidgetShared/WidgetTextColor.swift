import SwiftUI

/// `#RRGGBB` in the settings file, a `Color` on screen. Both targets draw the
/// clock, so both need the same conversion, and a stored hex is the only
/// colour representation two processes can agree on without a shared asset.
enum WidgetTextColor {
    /// The swatches Settings offers. White first: it is what reads on most
    /// photos, and the one the widget falls back to.
    static let swatches: [String] = [
        "#FFFFFF", "#000000", "#EB9526", "#F2E8D5",
        "#7FD1AE", "#8FC7E8", "#E88FA8", "#C7A8F0",
    ]

    static let fallbackHex = "#FFFFFF"

    static func color(hex: String) -> Color {
        guard let components = components(hex: hex) else { return .white }
        return Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: 1
        )
    }

    /// nil for anything that is not `#RRGGBB` / `RRGGBB`, so a hand-edited file
    /// cannot paint an invisible clock.
    static func components(hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func isValid(hex: String) -> Bool { components(hex: hex) != nil }
}

extension Font {
    /// The clock's face: the user's typeface at the given size, or the system
    /// font when they never chose one — and when a chosen face is not
    /// installed for this process, which is how a font another app installed
    /// behaves inside a widget extension.
    static func widgetClock(
        postScriptName: String,
        size: CGFloat,
        isBold: Bool,
        usesMonospacedDigits: Bool
    ) -> Font {
        if !postScriptName.isEmpty, let font = UIFont(name: postScriptName, size: size) {
            return Font(font)
        }
        var font = Font.system(
            size: size,
            weight: isBold ? .bold : .regular,
            design: .default
        )
        if usesMonospacedDigits { font = font.monospacedDigit() }
        return font
    }
}
