import CoreGraphics

/// How a strip of chips in the phone panel lays out (FS-03.12 §4).
///
/// A strip of **text chips** shares the width equally when it has five items or
/// fewer — every chip the same size, nothing to scroll — and scrolls at natural
/// widths past that. A strip of **swatches** (colour bands, point colours) always
/// shares the width: a swatch is 18–20pt, so even nine fit on a 375pt phone, and a
/// swatch that scrolled off would be a colour nobody knows is there.
enum EditorStripLayout {
    /// Text chips up to this count share the width equally.
    static let maximumEqualWidthChips = 5
    /// Gap between chips and inset from the panel edge — both on the spacing scale.
    static let chipSpacing: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let chipHeight: CGFloat = 30
    /// Icon (or colour dot) to title, inside a chip.
    static let chipIconSpacing: CGFloat = 4
    static let chipHorizontalPadding: CGFloat = 8

    enum Kind: Sendable {
        case text
        case swatch
    }

    static func sharesWidth(itemCount: Int, kind: Kind) -> Bool {
        switch kind {
        case .text: itemCount <= maximumEqualWidthChips
        case .swatch: true
        }
    }

    /// Width of one equal-width item in a strip `width` wide.
    static func equalItemWidth(itemCount: Int, in width: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let usable = width - horizontalInset * 2 - chipSpacing * CGFloat(itemCount - 1)
        return max(0, usable / CGFloat(itemCount))
    }
}
