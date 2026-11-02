import AppKit
import SwiftUI

/// The Mac's design tokens (DESIGN.md §10b, K4). The accent is ShotDex amber
/// on every Mac, whatever the system accent says (FS-18 AC-12).
enum MacTheme {
    /// `accent` of DESIGN.md §10b: `#C6730E` light, `#EB9526` dark.
    static let accent = dynamic(light: NSColor(red: 0xC6 / 255, green: 0x73 / 255, blue: 0x0E / 255, alpha: 1),
                                dark: NSColor(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255, alpha: 1))
    /// `fill2`: an empty tile, before or without its picture (board
    /// `MAC_ServerBrowser`, `t.fill2`).
    static let fill2 = dynamic(light: NSColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF4 / 255, alpha: 1),
                               dark: NSColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1))
    /// `rowSel`: a picked row that is not the focus — sidebar, tables, the
    /// folder columns (DESIGN.md §10b).
    static let rowSelection = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.10))
    /// `accentSoft`: the open folder's row in the server browser's columns
    /// (board `MAC_ServerBrowser`).
    static let accentSoft = dynamic(light: NSColor(red: 198 / 255, green: 115 / 255, blue: 14 / 255, alpha: 0.14),
                                    dark: NSColor(red: 235 / 255, green: 149 / 255, blue: 38 / 255, alpha: 0.18))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
