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

    /// Stored in place of a hex when the user picks **Smart**: the colour is
    /// not decided until the picture under the text has been measured, so
    /// there is no hex to store.
    static let smartHex = "smart"

    static func isSmart(hex: String) -> Bool {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == smartHex
    }

    /// Where white stops reading and black starts.
    ///
    /// Not the contrast-neutral crossover — by relative luminance alone white
    /// and black tie at about 0.18 — because the text is drawn with a shadow
    /// or a scrim behind it, and white carries far past that. Measured against
    /// the same kind of judgement `CoverTitleScrim` makes for album covers,
    /// which calls a cover bright at 0.42 *with* a scrim available; text that
    /// must stand without help needs the bar higher.
    static let smartCrossover: Double = 0.62

    /// White on a dark picture, black on a bright one.
    static func smartColor(luma: Double) -> Color {
        luma > smartCrossover ? .black : .white
    }

    /// The colour the face draws with, given what is behind it. `luma` is nil
    /// when there is no picture to measure — a widget with no photo, or an
    /// image that could not be read — and Smart then falls back to white,
    /// which is what the grey placeholder behind it wants anyway.
    static func color(hex: String, luma: Double?) -> Color {
        guard isSmart(hex: hex) else { return color(hex: hex) }
        guard let luma else { return .white }
        return smartColor(luma: luma)
    }

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

    /// What the settings file is allowed to hold: a real hex, or the Smart
    /// sentinel, which is deliberately *not* a valid hex and would otherwise be
    /// scrubbed back to white on the way through the store.
    static func isStorable(hex: String) -> Bool { isValid(hex: hex) || isSmart(hex: hex) }
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
