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

    /// `accentFill` / `onAccentFill`: the default push button's ground and
    /// its text (DESIGN.md §10b) — darker than `accent` in light.
    static let accentFill = dynamic(light: NSColor(red: 0xA3 / 255, green: 0x5E / 255, blue: 0x0A / 255, alpha: 1),
                                    dark: NSColor(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255, alpha: 1))
    static let onAccentFill = dynamic(light: .white, dark: .black)
    /// `sheet`: every sheet's ground, opaque (DESIGN.md §10b, one token).
    static let sheet = dynamic(light: NSColor(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 1),
                               dark: NSColor(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2D / 255, alpha: 1))
    /// `content`: the content area's ground, and a card's on a sheet.
    static let content = dynamic(light: .white, dark: NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1))
    /// `sep`: hairlines and card borders.
    static let separator = dynamic(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.10))
    /// `greenText`: a done state's words ("Added · 23,904 items", board `MAC_AddSource`).
    static let greenText = dynamic(light: NSColor(red: 0x1F / 255, green: 0x7A / 255, blue: 0x35 / 255, alpha: 1),
                                   dark: NSColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1))

    /// `redText`: a destructive command's words (Move, Delete) — darker than
    /// system red so it reads at 4.5:1 on a button's ground.
    static let redText = dynamic(light: NSColor(red: 0xC4 / 255, green: 0x00 / 255, blue: 0x1A / 255, alpha: 1),
                                 dark: NSColor(red: 0xFF / 255, green: 0x69 / 255, blue: 0x61 / 255, alpha: 1))
    /// `pressed`: a sheet button's resting ground (board `MAC_DeleteCopies`).
    static let pressed = dynamic(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.12))
    /// `checkboxStroke`: an empty checkbox's edge, on a `content` fill.
    static let checkboxStroke = dynamic(light: NSColor(white: 0, alpha: 0.25), dark: NSColor(white: 1, alpha: 0.30))

    /// `card`: a quiet panel on the content ground (Albums' recents, board `MAC_Collections`).
    static let card = dynamic(light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.055))

    /// `fill`: a flat control's ground (DESIGN.md §10b).
    static let fill = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.07))
    /// `greenSoft`: the tile behind a done job's check (board `MAC_Activity`).
    static let greenSoft = dynamic(light: NSColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 0.16),
                                   dark: NSColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 0.18))

    /// `rowAlt`: every other row of a table or list (DESIGN.md §10b).
    static let rowAlternate = dynamic(light: NSColor(white: 0, alpha: 0.03), dark: NSColor(white: 1, alpha: 0.04))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension MacTheme {
    /// Tier D, pixel surfaces (Compare): always dark, the values of the
    /// editor's `EditorTheme` (iOS target) — MAC_STYLE "Mac mindset".
    enum Editor {
        static let background = Color.black
        static let panel = Color(white: 0.055)
        static let hairline = Color.white.opacity(0.09)
        static let secondaryText = Color.white.opacity(0.55)
        /// `#EB9526`.
        static let accent = Color(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255)
    }
}
