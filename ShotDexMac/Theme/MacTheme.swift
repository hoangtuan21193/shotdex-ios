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

    /// `segOn`: a drawn segmented control's selected segment, raised
    /// (board `MAC_BackupOrganize`); `segShadow` under it.
    static let segmentOn = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.20))
    static let segmentShadow = dynamic(light: NSColor(white: 0, alpha: 0.18), dark: NSColor(white: 0, alpha: 0.30))

    /// `hud`: the full-screen viewer's floating controls over the photo — a dark
    /// glass (on `.ultraThinMaterial`) with a hairline and a soft shadow
    /// (board `MAC_ViewerFullScreen`); always dark, the photo decides nothing.
    static let hudFill = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.62)
    static let hudStroke = Color.white.opacity(0.12)
    static let hudSecondary = Color.white.opacity(0.62)
    static let hudSeparator = Color.white.opacity(0.16)

    /// `rowAlt`: every other row of a table or list (DESIGN.md §10b).
    static let rowAlternate = dynamic(light: NSColor(white: 0, alpha: 0.03), dark: NSColor(white: 1, alpha: 0.04))

    // MARK: Charts — style C (MAC_STYLE v3, DESIGN.md §3.4)

    /// A chart's ordinary marks: the accent at 38% (45% in dark).
    static let chartSoft = dynamic(light: NSColor(red: 0xC6 / 255, green: 0x73 / 255, blue: 0x0E / 255, alpha: 0.38),
                                   dark: NSColor(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255, alpha: 0.45))
    /// The area under a single line: 10% (14% in dark).
    static let chartArea = dynamic(light: NSColor(red: 0xC6 / 255, green: 0x73 / 255, blue: 0x0E / 255, alpha: 0.10),
                                   dark: NSColor(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255, alpha: 0.14))
    /// The six series colours, in this order, never cycled.
    static let chartSeries: [Color] = [
        dynamic(light: hex(0xC6730E), dark: hex(0xCF7F18)),
        dynamic(light: hex(0x3D6FB6), dark: hex(0x5C88E0)),
        dynamic(light: hex(0x1E9180), dark: hex(0x1F9C84)),
        dynamic(light: hex(0x9A4FA0), dark: hex(0xB070C8)),
        dynamic(light: hex(0x6F8A1E), dark: hex(0x7C962A)),
        dynamic(light: hex(0xB83E8C), dark: hex(0xD35E98)),
    ]
    /// A chart tooltip's ground and text (board `tip` / `onTip`).
    static let chartTip = dynamic(light: NSColor(red: 30 / 255, green: 30 / 255, blue: 32 / 255, alpha: 0.92),
                                  dark: NSColor(red: 242 / 255, green: 242 / 255, blue: 244 / 255, alpha: 0.95))
    static let onChartTip = dynamic(light: .white, dark: .black)

    private static func hex(_ value: Int) -> NSColor {
        NSColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

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
        /// `t.label`: text and glyphs at full weight.
        static let label = Color.white.opacity(0.92)
        /// `#0F1012`: a bar docked under the picture (Cull's shortcut strip).
        static let panelSolid = Color(red: 0x0F / 255, green: 0x10 / 255, blue: 0x12 / 255)
        /// A key drawn in a legend (`⌘Z`): its ground and its edge.
        static let keycapFill = Color.white.opacity(0.06)
        static let keycapStroke = Color.white.opacity(0.28)
        /// Over a Rejected photo's tile: it reads as set aside.
        static let rejectedShade = Color.black.opacity(0.55)
        /// `#EB9526`.
        static let accent = Color(red: 0xEB / 255, green: 0x95 / 255, blue: 0x26 / 255)

        // The photo editor (board `MAC_Edit`).
        /// `#0E0E0E`: the inspector's ground.
        static let inspector = Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x0E / 255)
        /// `#1C1C1C`: a card in the inspector (the histogram).
        static let control = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)
        /// A value field: its ground and its edge.
        static let field = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
        static let fieldStroke = Color.white.opacity(0.10)
        /// `#2A2A2A`: a slider's rail.
        static let sliderTrack = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
        /// A pressed or on control.
        static let pressed = Color.white.opacity(0.12)
        /// The toolbar's glass capsule.
        static let glass = Color(red: 30 / 255, green: 30 / 255, blue: 32 / 255).opacity(0.74)
        static let glassStroke = Color.white.opacity(0.10)
        /// The histogram's channels, screened over each other.
        static let channelRed = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
        static let channelGreen = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        static let channelBlue = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
        static let histogramRed = channelRed.opacity(0.6)
        static let histogramGreen = channelGreen.opacity(0.55)
        static let histogramBlue = channelBlue.opacity(0.6)

        // Inspector controls (board `MAC_EditColor`).
        /// `fill2`: a segmented control's track, with a hairline edge.
        static let segmentTrack = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
        /// `segOn`: the chosen segment, an on button.
        static let segmentOn = Color.white.opacity(0.20)
        static let segmentRadius: CGFloat = 4
        /// A card drawn on the inspector (the curve).
        static let cardRadius: CGFloat = 8
        static let cardFill = Color.white.opacity(0.03)
        static let curveGrid = Color.white.opacity(0.08)
        static let curveHistogram = Color.white.opacity(0.10)
        static let curveGuide = Color.white.opacity(0.28)
        /// `t.fill`: a push button or pill on the inspector.
        static let fill = Color.white.opacity(0.07)
        /// `rowSel`: the picked row of an inspector list.
        static let rowSelected = Color.white.opacity(0.10)
        /// Push buttons and list rows in the inspector (`controlRadius` is the small controls').
        static let buttonRadius: CGFloat = 8
        /// The mask overlay's red (the renderer's tint, as a swatch).
        static let maskOverlay = Color(red: 1, green: 0.23, blue: 0.19)
        /// A list row's little picture: corner and edge.
        static let thumbnailRadius: CGFloat = 3
        static let thumbnailStroke = Color.white.opacity(0.18)
        /// The ± / ∩ badge on a mask's area row.
        static let badgeFill = Color.white.opacity(0.16)
        /// `t.dim`: what is there but not in force (a history step past the one shown).
        static let dim = Color.white.opacity(0.35)
        /// A layer's turn knob over the photo.
        static let knobFill = Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255).opacity(0.85)
        /// A text layer's tile in the layer list (shapes tint it with their colour).
        static let layerTile = Color.white.opacity(0.14)
        /// Over the photo: a tool's lines in white with a dark halo.
        static let overlayHalo = Color.black.opacity(0.55)
        /// Under small text laid over a picture (the curve readout, the loupe's hex).
        static let readoutShade = Color.black.opacity(0.72)

        // The crop frame (board `MAC_EditCrop`).
        /// Over the photo outside the frame.
        static let cropDim = Color.black.opacity(0.62)
        /// The thirds; brighter while a handle is held.
        static let cropGrid = Color.white.opacity(0.38)
        static let cropGridActive = Color.white.opacity(0.55)
        static let cropOutline = Color.white.opacity(0.9)
        /// Icon buttons and wide buttons in the inspector.
        static let controlRadius: CGFloat = 6
    }
}
